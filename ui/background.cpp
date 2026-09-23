#include "background.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
BackgroundMonitor::BackgroundMonitor(QObject *parent) : QObject(parent) {
  m_enabled = m_settings.value("backgroundMonitoring", true).toBool();
  m_status = m_enabled ? "Background monitoring starts when the app launches" : "Background monitoring is off";
  m_process.setProcessChannelMode(QProcess::MergedChannels);
  m_timeout.setSingleShot(true);
  m_retry.setSingleShot(true);
  m_retry.setInterval(200);
  connect(&m_retry, &QTimer::timeout, this, &BackgroundMonitor::checkReady);
  connect(&m_timeout, &QTimer::timeout, this, [this] {
    m_timedOut = true;
    if (m_process.state() != QProcess::NotRunning) m_process.kill();
    else complete(false, "Collector did not become ready; check the user service");
  });
  connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
    if (error == QProcess::FailedToStart) complete(false, m_process.errorString());
  });
  connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
          [this](int code, QProcess::ExitStatus exit) {
    const auto output = QString::fromUtf8(m_process.readAll()).left(200).trimmed();
    if (m_timedOut) {
      complete(false, "Service request timed out; its state could not be confirmed");
    } else if (m_checking) {
      if (code == 0 && exit == QProcess::NormalExit) complete(true);
      else m_retry.start();
    } else if (code != 0 || exit != QProcess::NormalExit) {
      complete(false, output);
    } else if (m_requested) {
      // systemctl accepting a start is not proof that the collector stayed alive.
      m_checking = true;
      m_timeout.start(5000);
      m_retry.start();
    } else {
      complete(true);
    }
  });
}
BackgroundMonitor::~BackgroundMonitor() {
  m_timeout.stop(); m_retry.stop(); m_process.disconnect(this);
  if (m_process.state() != QProcess::NotRunning) { m_process.kill(); m_process.waitForFinished(300); }
}
void BackgroundMonitor::initialize() {
  if (m_enabled) setEnabled(true);
}
void BackgroundMonitor::setEnabled(bool enabled) {
  if (busy()) return;
  m_requested = enabled; m_timedOut = false; m_checking = false; m_busy = true;
  m_status = enabled ? "Starting background monitoring…" : "Stopping background monitoring…";
  m_process.start("/usr/bin/systemctl", {"--user", enabled ? "enable" : "disable", "--now", "omarchy-task-manager-monitor.service"});
  m_timeout.start(8000); emit changed();
}
void BackgroundMonitor::checkReady() {
  const auto adjacent = QCoreApplication::applicationDirPath() + "/omarchy-task-manager-core";
  const auto installed = QDir(QCoreApplication::applicationDirPath()).absoluteFilePath("../lib/omarchy-task-manager/omarchy-task-manager-core");
  m_process.start(QFileInfo::exists(adjacent) ? adjacent : installed, {"--monitor-status"});
}
void BackgroundMonitor::complete(bool success, const QString &error) {
  m_timeout.stop(); m_retry.stop(); m_busy = false;
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
