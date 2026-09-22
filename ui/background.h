#pragma once
#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QTimer>
class BackgroundMonitor : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
  Q_PROPERTY(bool busy READ busy NOTIFY changed)
  Q_PROPERTY(QString status READ status NOTIFY changed)
public:
  explicit BackgroundMonitor(QObject *parent = nullptr);
  ~BackgroundMonitor() override;
  bool enabled() const { return m_enabled; }
  bool busy() const { return m_process.state() != QProcess::NotRunning; }
  QString status() const { return m_status; }
  void initialize();
  Q_INVOKABLE void setEnabled(bool enabled);
signals:
  void changed();
private:
  void complete(bool success, const QString &error = {});
  QProcess m_process;
  QTimer m_timeout;
  QSettings m_settings;
  bool m_enabled = true, m_requested = true, m_timedOut = false;
  QString m_status;
};
