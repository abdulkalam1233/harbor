#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>

class SelfUsage : public QObject {
    Q_OBJECT
    Q_PROPERTY(double cpuPercent READ cpuPercent NOTIFY changed)
    Q_PROPERTY(double memoryBytes READ memoryBytes NOTIFY changed)

public:
    explicit SelfUsage(const QString &procDirectory = "/proc/self", int sampleInterval = 3000,
                       QObject *parent = nullptr);

    double cpuPercent() const { return m_cpuPercent; }
    double memoryBytes() const { return m_memoryBytes; }

    static qint64 parseCpuTicks(const QByteArray &stat);
    static qint64 parseResidentBytes(const QByteArray &status);

signals:
    void changed();

private:
    void sample();
    QByteArray read(const QString &name) const;

    QString m_procDirectory;
    QTimer m_timer;
    QElapsedTimer m_sinceLastSample;
    qint64 m_lastTicks = -1;
    double m_cpuPercent = 0;
    double m_memoryBytes = 0;
};
