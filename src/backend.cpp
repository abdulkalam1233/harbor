#include "backend.h"

#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <utility>

namespace {

const int LogTailLines = 200;

const QHash<QString, QStringList> &actionArguments() {
    static const QHash<QString, QStringList> arguments{
        {"start", {"start"}},
        {"stop", {"stop"}},
        {"restart", {"restart"}},
        {"remove", {"rm", "-f"}},
    };
    return arguments;
}

QString missingDockerMessage() {
    return Backend::tr("Docker isn't installed. Install it with: %1").arg("sudo pacman -S docker");
}

}

Backend::Backend(const QString &docker, int refreshInterval, QObject *parent)
    : QObject(parent), m_docker(docker.isEmpty() ? QStandardPaths::findExecutable("docker") : docker) {
    connect(&m_timer, &QTimer::timeout, this, &Backend::refresh);
    if (refreshInterval > 0) {
        m_timer.setInterval(refreshInterval);
        m_timer.start();
    }
    refresh();
}

void Backend::refresh() {
    // A refresh asked for while one is running (say, right after an action)
    // must still see the action's result, so it runs once the current one ends.
    if (m_refreshing) {
        m_refreshAgain = true;
        return;
    }
    m_refreshing = true;
    runDocker({"ps", "--all", "--no-trunc", "--format", "{{json .}}"}, [this](const DockerResult &result) {
        m_refreshing = false;
        setError(result.succeeded ? QString() : result.failure);
        if (result.succeeded)
            setContainers(parseContainers(result.output));
        if (std::exchange(m_refreshAgain, false))
            refresh();
    });
    fetchStats();
    if (!m_logsId.isEmpty())
        fetchLogs();
}

void Backend::perform(const QString &action, const QString &id) {
    const QStringList arguments = actionArguments().value(action);
    if (arguments.isEmpty() || id.isEmpty() || m_busyIds.contains(id))
        return;
    setBusy(id, true);
    runDocker(arguments + QStringList{id}, [this, action, id](const DockerResult &result) {
        setBusy(id, false);
        if (!result.succeeded)
            emit actionFailed(result.failure);
        else if (action == "remove" && id == m_logsId)
            closeLogs();
        refresh();
    });
}

void Backend::performEach(const QString &action, const QStringList &ids) {
    for (const QString &id : ids)
        perform(action, id);
}

void Backend::openLogs(const QString &id, const QString &name) {
    m_logsId = id;
    m_logsName = name;
    m_logs.clear();
    emit logsChanged();
    fetchLogs();
}

void Backend::closeLogs() {
    m_logsId.clear();
    m_logsName.clear();
    m_logs.clear();
    emit logsChanged();
}

QVariantList Backend::parseContainers(const QByteArray &output) {
    QVariantList containers;
    for (const QByteArray &line : output.split('\n')) {
        const QJsonObject json = QJsonDocument::fromJson(line).object();
        const QString id = json.value("ID").toString();
        if (id.isEmpty())
            continue;
        containers.append(QVariantMap{
            {"id", id},
            {"name", json.value("Names").toString()},
            {"image", json.value("Image").toString()},
            {"state", json.value("State").toString()},
            {"status", json.value("Status").toString()},
            {"ports", json.value("Ports").toString()},
        });
    }
    return containers;
}

QVariantMap Backend::parseStats(const QByteArray &output) {
    QVariantMap stats;
    for (const QByteArray &line : output.split('\n')) {
        const QJsonObject json = QJsonDocument::fromJson(line).object();
        const QString id = json.value("ID").toString();
        if (id.isEmpty())
            continue;
        const QString memoryUsedOfLimit = json.value("MemUsage").toString();
        stats.insert(id, QVariantMap{
            {"cpu", json.value("CPUPerc").toString()},
            {"memory", memoryUsedOfLimit.section(" / ", 0, 0)},
        });
    }
    return stats;
}

QString Backend::describeFailure(const QString &message) {
    const QString trimmed = message.trimmed();
    const QList<QPair<QString, QString>> knownFailures{
        {"permission denied while trying to connect",
         tr("Docker refused access. Add yourself to the docker group, then log out and back in: %1")
             .arg("sudo usermod -aG docker $USER")},
        {"Cannot connect to the Docker daemon",
         tr("Docker isn't running. Start it with: %1").arg("sudo systemctl enable --now docker")},
    };
    for (const auto &[symptom, explanation] : knownFailures)
        if (trimmed.contains(symptom, Qt::CaseInsensitive))
            return explanation;
    return trimmed.isEmpty() ? tr("Docker failed without saying why.") : trimmed;
}

void Backend::runDocker(const QStringList &arguments, const Completion &completion,
                        QProcess::ProcessChannelMode mode) {
    if (m_docker.isEmpty()) {
        completion({false, {}, missingDockerMessage()});
        return;
    }
    auto *process = new QProcess(this);
    process->setProcessChannelMode(mode);
    connect(process, &QProcess::finished, this, [process, completion](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (status == QProcess::NormalExit && code == 0) {
            completion({true, process->readAllStandardOutput(), {}});
            return;
        }
        const QString message = QString::fromUtf8(process->readAllStandardError() + process->readAllStandardOutput());
        completion({false, {}, describeFailure(message)});
    });
    // A process that never starts never finishes, so it reports here instead.
    connect(process, &QProcess::errorOccurred, this, [process, completion](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        completion({false, {}, missingDockerMessage()});
    });
    process->start(m_docker, arguments);
}

void Backend::fetchLogs() {
    const QString id = m_logsId;
    // Containers write to both stdout and stderr, and the log is both, in order.
    runDocker({"logs", "--tail", QString::number(LogTailLines), id}, [this, id](const DockerResult &result) {
        if (id == m_logsId)
            setLogs(result.succeeded ? QString::fromUtf8(result.output) : result.failure);
    }, QProcess::MergedChannels);
}

void Backend::fetchStats() {
    // docker stats samples for about a second, so a slow one is skipped rather than queued.
    if (m_fetchingStats)
        return;
    m_fetchingStats = true;
    runDocker({"stats", "--no-stream", "--no-trunc", "--format", "{{json .}}"}, [this](const DockerResult &result) {
        m_fetchingStats = false;
        const QVariantMap stats = result.succeeded ? parseStats(result.output) : QVariantMap();
        if (stats == m_stats)
            return;
        m_stats = stats;
        emit statsChanged();
    });
}

void Backend::setContainers(const QVariantList &containers) {
    if (m_loaded && containers == m_containers)
        return;
    m_loaded = true;
    m_containers = containers;
    emit containersChanged();
}

void Backend::setError(const QString &error) {
    if (error == m_error)
        return;
    m_error = error;
    emit errorChanged();
}

void Backend::setBusy(const QString &id, bool busy) {
    if (busy)
        m_busyIds.append(id);
    else
        m_busyIds.removeAll(id);
    emit busyIdsChanged();
}

void Backend::setLogs(const QString &logs) {
    if (logs == m_logs)
        return;
    m_logs = logs;
    emit logsChanged();
}
