#include "selfusage.h"

#include <QFile>
#include <unistd.h>

namespace {

const int UserTimeField = 11;
const int SystemTimeField = 12;

}

SelfUsage::SelfUsage(const QString &procDirectory, int sampleInterval, QObject *parent)
    : QObject(parent), m_procDirectory(procDirectory) {
    connect(&m_timer, &QTimer::timeout, this, &SelfUsage::sample);
    if (sampleInterval > 0) {
        m_timer.setInterval(sampleInterval);
        m_timer.start();
    }
    sample();
}

// Fields are counted from the one after the command name, which is in
// parentheses and may itself contain spaces and parentheses.
qint64 SelfUsage::parseCpuTicks(const QByteArray &stat) {
    const int nameEnd = stat.lastIndexOf(')');
    if (nameEnd < 0)
        return -1;
    const QList<QByteArray> fields = stat.mid(nameEnd + 1).simplified().split(' ');
    if (fields.size() <= SystemTimeField)
        return -1;
    return fields.at(UserTimeField).toLongLong() + fields.at(SystemTimeField).toLongLong();
}

qint64 SelfUsage::parseResidentBytes(const QByteArray &status) {
    for (const QByteArray &line : status.split('\n'))
        if (line.startsWith("VmRSS:"))
            return line.mid(6).simplified().split(' ').first().toLongLong() * 1024;
    return 0;
}

void SelfUsage::sample() {
    const qint64 ticks = parseCpuTicks(read("stat"));
    const qint64 elapsedMs = m_sinceLastSample.restart();
    if (m_lastTicks >= 0 && ticks >= m_lastTicks && elapsedMs > 0)
        m_cpuPercent = 100.0 * (ticks - m_lastTicks) * 1000 / sysconf(_SC_CLK_TCK) / elapsedMs;
    m_lastTicks = ticks;
    m_memoryBytes = parseResidentBytes(read("status"));
    emit changed();
}

QByteArray SelfUsage::read(const QString &name) const {
    QFile file(m_procDirectory + "/" + name);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
