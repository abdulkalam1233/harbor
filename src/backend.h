#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <functional>

struct DockerResult {
    bool succeeded = false;
    QByteArray output;
    QString failure;
};

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList containers READ containers NOTIFY containersChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY containersChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QVariantMap stats READ stats NOTIFY statsChanged)
    Q_PROPERTY(QStringList busyIds READ busyIds NOTIFY busyIdsChanged)
    Q_PROPERTY(QString logsId READ logsId NOTIFY logsChanged)
    Q_PROPERTY(QString logsName READ logsName NOTIFY logsChanged)
    Q_PROPERTY(QString logs READ logs NOTIFY logsChanged)

public:
    explicit Backend(const QString &docker = {}, int refreshInterval = 3000, QObject *parent = nullptr);

    QVariantList containers() const { return m_containers; }
    bool loaded() const { return m_loaded; }
    QString error() const { return m_error; }
    QVariantMap stats() const { return m_stats; }
    QStringList busyIds() const { return m_busyIds; }
    QString logsId() const { return m_logsId; }
    QString logsName() const { return m_logsName; }
    QString logs() const { return m_logs; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void perform(const QString &action, const QString &id);
    Q_INVOKABLE void performEach(const QString &action, const QStringList &ids);
    Q_INVOKABLE void openLogs(const QString &id, const QString &name);
    Q_INVOKABLE void closeLogs();

    static QVariantList parseContainers(const QByteArray &output);
    static QVariantMap parseStats(const QByteArray &output);
    static QString describeFailure(const QString &message);

signals:
    void containersChanged();
    void errorChanged();
    void statsChanged();
    void busyIdsChanged();
    void logsChanged();
    void actionFailed(const QString &message);

private:
    using Completion = std::function<void(const DockerResult &)>;

    void runDocker(const QStringList &arguments, const Completion &completion,
                   QProcess::ProcessChannelMode mode = QProcess::SeparateChannels);
    void fetchLogs();
    void fetchStats();
    void setContainers(const QVariantList &containers);
    void setError(const QString &error);
    void setBusy(const QString &id, bool busy);
    void setLogs(const QString &logs);

    QString m_docker;
    QTimer m_timer;
    QVariantList m_containers;
    bool m_loaded = false;
    bool m_refreshing = false;
    bool m_refreshAgain = false;
    QString m_error;
    QVariantMap m_stats;
    bool m_fetchingStats = false;
    QStringList m_busyIds;
    QString m_logsId;
    QString m_logsName;
    QString m_logs;
};
