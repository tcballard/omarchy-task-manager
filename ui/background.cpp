#include "background.h"
BackgroundMonitor::BackgroundMonitor(QObject *parent) : QObject(parent) {
  m_enabled = m_settings.value("backgroundMonitoring", true).toBool();
  m_status = m_enabled ? "Background monitoring starts when the app launches" : "Background monitoring is off";
  m_process.setProcessChannelMode(QProcess::MergedChannels);
  m_timeout.setSingleShot(true);
  m_timeout.setInterval(8000);
  connect(&m_timeout, &QTimer::timeout, this, [this] { m_timedOut = true; m_process.kill(); });
  connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
    if (error == QProcess::FailedToStart) complete(false, m_process.errorString());
  });
  connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
          [this](int code, QProcess::ExitStatus exit) {
    complete(!m_timedOut && code == 0 && exit == QProcess::NormalExit,
             m_timedOut ? "Service request timed out; its state could not be confirmed"
                        : QString::fromUtf8(m_process.readAll()).left(200).trimmed());
  });
}
BackgroundMonitor::~BackgroundMonitor() {
  m_timeout.stop(); m_process.disconnect(this);
  if (m_process.state() != QProcess::NotRunning) { m_process.kill(); m_process.waitForFinished(300); }
}
void BackgroundMonitor::initialize() {
  if (m_enabled) setEnabled(true);
}
void BackgroundMonitor::setEnabled(bool enabled) {
  if (busy()) return;
  m_requested = enabled; m_timedOut = false;
  m_status = enabled ? "Starting background monitoring…" : "Stopping background monitoring…";
  m_process.start("/usr/bin/systemctl", {"--user", enabled ? "enable" : "disable", "--now", "omarchy-task-manager-monitor.service"});
  m_timeout.start(); emit changed();
}
void BackgroundMonitor::complete(bool success, const QString &error) {
  m_timeout.stop();
  if (success) {
    m_enabled = m_requested;
    m_settings.setValue("backgroundMonitoring", m_enabled);
    m_status = m_enabled ? "Background collection enabled · retains up to 60 seconds"
                         : "Background monitoring is off · collects only while the app runs";
  } else {
    m_status = "Background monitoring could not be changed. Install the updated package and retry. " + error;
  }
  emit changed();
}
