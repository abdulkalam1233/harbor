#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "selfusage.h"
#include "theme.h"
#include "translator.h"

namespace {

const QByteArray TwoContainers =
    R"({"ID":"aaa111","Names":"web","Image":"nginx:latest","State":"running","Status":"Up 2 hours","Ports":"0.0.0.0:8080->80/tcp"})"
    "\n"
    R"({"ID":"bbb222","Names":"db","Image":"postgres:17","State":"exited","Status":"Exited (0) 3 days ago","Ports":""})"
    "\n";

const QByteArray WebStats =
    R"({"ID":"aaa111","Name":"web","CPUPerc":"1.22%","MemUsage":"102.2MiB / 31.02GiB","MemPerc":"0.32%"})"
    "\n";

}

class HarborTests : public QObject {
    Q_OBJECT

private slots:
    void parsesDockerPsJsonLines()
    {
        const QVariantList containers = Backend::parseContainers(TwoContainers + "\nnot json\n");
        QCOMPARE(containers.size(), 2);
        const QVariantMap web = containers.first().toMap();
        QCOMPARE(web.value("id").toString(), QString("aaa111"));
        QCOMPARE(web.value("name").toString(), QString("web"));
        QCOMPARE(web.value("image").toString(), QString("nginx:latest"));
        QCOMPARE(web.value("state").toString(), QString("running"));
        QCOMPARE(web.value("ports").toString(), QString("0.0.0.0:8080->80/tcp"));
        QCOMPARE(containers.last().toMap().value("state").toString(), QString("exited"));
    }

    void parsesDockerStatsJsonLines()
    {
        const QVariantMap stats = Backend::parseStats(WebStats + "\nnot json\n");
        QCOMPARE(stats.size(), 1);
        const QVariantMap web = stats.value("aaa111").toMap();
        QCOMPARE(web.value("cpu").toString(), QString("1.22%"));
        QCOMPARE(web.value("memory").toString(), QString("102.2MiB"));
    }

    void refreshReportsCpuAndMemoryOfRunningContainers()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        QTRY_VERIFY(backend.stats().contains("aaa111"));
        QCOMPARE(backend.stats().value("aaa111").toMap().value("memory").toString(), QString("102.2MiB"));
        QVERIFY(!backend.stats().contains("bbb222"));
    }

    void explainsKnownDockerFailures()
    {
        QVERIFY(Backend::describeFailure(
                    "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock")
                    .contains("usermod -aG docker"));
        QVERIFY(Backend::describeFailure("Cannot connect to the Docker daemon at unix:///var/run/docker.sock.")
                    .contains("systemctl"));
        QCOMPARE(Backend::describeFailure("  Error response from daemon: conflict \n"),
                 QString("Error response from daemon: conflict"));
        QVERIFY(!Backend::describeFailure("").isEmpty());
    }

    void refreshListsContainers()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        QTRY_COMPARE(backend.containers().size(), 2);
        QVERIFY(backend.loaded());
        QVERIFY(backend.error().isEmpty());
    }

    void refreshReportsFailures()
    {
        QTemporaryDir dir;
        write(dir.filePath("fail"), "permission denied while trying to connect to the docker API");
        Backend backend(fakeDocker(dir), 0);
        QTRY_VERIFY(backend.error().contains("docker group"));
        QVERIFY(!backend.loaded());
    }

    void reportsMissingDocker()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("no-such-docker"), 0);
        QTRY_VERIFY(backend.error().contains("isn't installed"));
    }

    void actionsRunTheMatchingDockerCommand()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        QTRY_COMPARE(backend.containers().size(), 2);

        backend.perform("stop", "aaa111");
        QVERIFY(backend.busyIds().contains("aaa111"));
        QTRY_VERIFY(backend.busyIds().isEmpty());
        backend.perform("remove", "bbb222");
        QTRY_VERIFY(backend.busyIds().isEmpty());

        QTRY_VERIFY(calls(dir).contains("stop aaa111"));
        QVERIFY(calls(dir).contains("rm -f bbb222"));
    }

    void bulkActionsRunOnEveryContainer()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        QTRY_VERIFY(backend.loaded());

        backend.performEach("start", {"aaa111", "bbb222"});
        QCOMPARE(backend.busyIds(), QStringList({"aaa111", "bbb222"}));
        QTRY_VERIFY(backend.busyIds().isEmpty());

        QTRY_VERIFY(calls(dir).contains("start aaa111"));
        QVERIFY(calls(dir).contains("start bbb222"));
    }

    void ignoresUnknownActions()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        QTRY_VERIFY(backend.loaded());
        backend.perform("prune", "aaa111");
        QVERIFY(backend.busyIds().isEmpty());
        QVERIFY(!calls(dir).contains("prune"));
    }

    void failedActionsAreAnnounced()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        QTRY_VERIFY(backend.loaded());
        write(dir.filePath("fail"), "Error response from daemon: No such container: zzz");

        QSignalSpy failed(&backend, &Backend::actionFailed);
        backend.perform("start", "zzz");
        QTRY_COMPARE(failed.size(), 1);
        QCOMPARE(failed.first().first().toString(), QString("Error response from daemon: No such container: zzz"));
    }

    void showsLogsAndClosesThemOnRemove()
    {
        QTemporaryDir dir;
        Backend backend(fakeDocker(dir), 0);
        backend.openLogs("aaa111", "web");
        QTRY_COMPARE(backend.logs(), QString("log line from aaa111\n"));
        QCOMPARE(backend.logsName(), QString("web"));

        backend.perform("remove", "aaa111");
        QTRY_VERIFY(backend.logsId().isEmpty());
        QVERIFY(backend.logs().isEmpty());
    }

    void readsHarborsOwnCpuTimeAndMemory()
    {
        QCOMPARE(SelfUsage::parseCpuTicks("4242 (my (odd) app) S 1 4242 4242 0 -1 4194560 900 0 0 0 150 30 0 0 20 0"),
                 qint64(180));
        QCOMPARE(SelfUsage::parseCpuTicks("garbage"), qint64(-1));
        QCOMPARE(SelfUsage::parseResidentBytes("Name:\tharbor\nVmRSS:\t   48212 kB\nThreads:\t9\n"), qint64(48212 * 1024));

        QTemporaryDir dir;
        write(dir.filePath("stat"), "4242 (harbor) S 1 4242 4242 0 -1 4194560 900 0 0 0 150 30 0 0 20 0");
        write(dir.filePath("status"), "VmRSS:\t2048 kB\n");
        SelfUsage usage(dir.path(), 0);
        QCOMPARE(usage.memoryBytes(), 2048.0 * 1024);
        QCOMPARE(usage.cpuPercent(), 0.0);
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/colors.toml", "accent = \"#112233\"\n");

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json"), command = dir.filePath("hyprctl");
        writeExecutable(command, "#!/bin/sh\ncat '" + response.toUtf8() + "'\n");
        write(response, "{\"int\":0}");

        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        write(response, "{\"int\":6}");
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Remove").isNull());
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Remove": "Remover", "Close": "Fechar"})");
        write(dir.path() + "/pt-BR.json", R"({"Remove": "Excluir"})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Remove"), QString("Excluir"));
        QCOMPARE(translator.translate("Main", "Close"), QString("Fechar"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void bundledCatalogsAreValid()
    {
        const QString catalogs = QFileInfo(QFINDTESTDATA("../src/i18n/da.json")).absolutePath();
        QTemporaryDir dir;
        Translator english(dir.path() + "/language", catalogs);
        QCOMPARE(english.translate("Main", "%n containers", nullptr, 1), QString("%n container"));
        QCOMPARE(english.translate("Main", "%n containers", nullptr, 3), QString("%n containers"));

        write(dir.path() + "/language", "da\n");
        Translator danish(dir.path() + "/language", catalogs);
        QCOMPARE(danish.translate("Main", "Remove"), QString("Fjern"));
        QCOMPARE(danish.translate("Main", "%n containers", nullptr, 3), QString("%n containere"));
    }

private:
    // A stand-in for the docker CLI: it records each call, answers ps and logs
    // with canned output, and fails with the text of a "fail" file when present.
    static QString fakeDocker(const QTemporaryDir &dir)
    {
        write(dir.filePath("ps.jsonl"), TwoContainers);
        write(dir.filePath("stats.jsonl"), WebStats);
        const QByteArray root = dir.path().toUtf8();
        const QString script = dir.filePath("docker");
        writeExecutable(script,
            "#!/bin/sh\n"
            "echo \"$@\" >> '" + root + "/calls'\n"
            "if [ -f '" + root + "/fail' ]; then cat '" + root + "/fail' >&2; exit 1; fi\n"
            "case \"$1\" in\n"
            "  ps) cat '" + root + "/ps.jsonl' ;;\n"
            "  stats) cat '" + root + "/stats.jsonl' ;;\n"
            "  logs) echo \"log line from $4\" ;;\n"
            "  *) echo \"$2\" ;;\n"
            "esac\n");
        return script;
    }

    static QString calls(const QTemporaryDir &dir)
    {
        QFile file(dir.filePath("calls"));
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
    }

    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }

    static void writeExecutable(const QString &path, const QByteArray &contents)
    {
        write(path, contents);
        QVERIFY(QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    }
};

QTEST_MAIN(HarborTests)
#include "harbor_tests.moc"
