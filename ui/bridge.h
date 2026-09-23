#pragma once
#include "background.h"
#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QProcess>
#include <QSettings>
#include <QTimer>
#include <QVariantMap>
class Rows : public QAbstractListModel {
  Q_OBJECT
public:
  explicit Rows(QObject *parent = nullptr) : QAbstractListModel(parent) {}
  int rowCount(const QModelIndex &p = {}) const override {
    return p.isValid() ? 0 : rows.size();
  }
  QVariant data(const QModelIndex &i, int role) const override {
    return i.isValid() && i.row() < rows.size() && role == Qt::UserRole + 1
               ? rows[i.row()]
               : QVariant();
  }
  QHash<int, QByteArray> roleNames() const override {
    return {{Qt::UserRole + 1, "entry"}};
  }
  void replace(const QVariantList &next);
  QVariantList rows;
};
class Bridge : public QObject {
  Q_OBJECT
  Q_PROPERTY(Rows *rows READ rows CONSTANT)
  Q_PROPERTY(BackgroundMonitor *background READ background CONSTANT)
  Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY snapshotChanged)
  Q_PROPERTY(QString page READ page WRITE setPage NOTIFY preferencesChanged)
  Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY preferencesChanged)
  Q_PROPERTY(QString sort READ sort WRITE setSort NOTIFY preferencesChanged)
  Q_PROPERTY(bool descending READ descending WRITE setDescending NOTIFY
                 preferencesChanged)
  Q_PROPERTY(bool tree READ tree WRITE setTree NOTIFY preferencesChanged)
  Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY preferencesChanged)
  Q_PROPERTY(
      int interval READ interval WRITE setInterval NOTIFY preferencesChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
  Q_PROPERTY(
      QString selected READ selected WRITE setSelected NOTIFY selectionChanged)
  Q_PROPERTY(QVariantMap selection READ selection NOTIFY selectionChanged)
  Q_PROPERTY(QVariantMap inspection READ inspection NOTIFY inspectionChanged)
  Q_PROPERTY(QVariantList history READ history NOTIFY snapshotChanged)
public:
  explicit Bridge(QObject *parent = nullptr);
  ~Bridge() override;
  BackgroundMonitor *background() { return &m_background; }
  Rows *rows() { return &m_rows; }
  QVariantMap snapshot() const { return m_snapshot; }
  QString page() const { return m_page; }
  QString query() const { return m_query; }
  QString sort() const { return m_sort; }
  bool descending() const { return m_descending; }
  bool tree() const { return m_tree; }
  bool paused() const { return m_paused; }
  int interval() const { return m_interval; }
  QString status() const { return m_status; }
  bool busy() const { return m_busy; }
  QString selected() const { return m_selected; }
  QVariantMap selection() const;
  QVariantMap inspection() const { return m_inspection; }
  QVariantList history() const { return m_history; }
  void setPage(const QString &);
  void setQuery(const QString &);
  void setSort(const QString &);
  void setDescending(bool);
  void setTree(bool);
  void setPaused(bool);
  void setInterval(int);
  void setSelected(const QString &);
  Q_INVOKABLE void refresh();
  Q_INVOKABLE QVariantMap prepareManagement(const QVariantMap &request);
  Q_INVOKABLE void inspect();
  Q_INVOKABLE void dismissInspection();
  Q_INVOKABLE void loadLogs();
  Q_INVOKABLE void launch(const QString &command);
  Q_INVOKABLE void openExecutable();
  Q_INVOKABLE void copyDetails();
  Q_INVOKABLE void exportSnapshot();
  Q_INVOKABLE void filterUser(int uid);
  Q_INVOKABLE void floatPanel(int width, int height);
  Q_INVOKABLE QVariantMap prepareAction(bool force);
  Q_INVOKABLE QVariantMap prepareTree(bool force);
  Q_INVOKABLE void confirmAction();
  Q_INVOKABLE void cancelAction();
  Q_INVOKABLE void windowAction(bool close);
  Q_INVOKABLE void selectOffset(int offset);
  Q_INVOKABLE QString bytes(double value) const;
  Q_INVOKABLE QString percent(const QVariant &value) const;
  Q_INVOKABLE QString details() const;
  Q_INVOKABLE QVariant preference(const QString &key,
                                  const QVariant &fallback) const;
  Q_INVOKABLE void savePreference(const QString &key, const QVariant &value);
signals:
  void inspectionChanged();
  void inspectionRequested();
  void snapshotChanged();
  void preferencesChanged();
  void selectionChanged();
  void statusChanged();
  void busyChanged();

private:
  friend class BridgeTest;
  void handleResponse(const QVariantMap &);
  void beginInspection(const QVariantMap &, const QString &);
  void failInspection(const QString &);
  bool m_inspecting = false, m_inspectionPending = false;
  bool send(const QVariantMap &);
  static bool validPage(const QString &);
  void receive();
  void rebuild();
  void message(const QString &);
  void finish();
  BackgroundMonitor m_background;
  bool m_restoreBackground = true;
  Rows m_rows;
  QProcess m_worker;
  QTimer m_timer, m_timeout;
  QSettings m_settings;
  QByteArray m_buffer;
  QVariantMap m_snapshot, m_pending, m_inspection;
  int m_userFilter = -1;
  QVariantList m_history;
  QElapsedTimer m_clock, m_feedback;
  QString m_page = "apps", m_query, m_sort = "cpu",
          m_status = "Starting monitor…", m_selected;
  bool m_descending = true, m_tree = false, m_paused = false,
       m_busy = false, m_resetSample = true;
  int m_interval = 1000;
};
