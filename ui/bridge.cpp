#include "bridge.h"
#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <functional>
void Rows::replace(const QVariantList &next) {
  if (rows.size() != next.size()) {
    beginResetModel();
    rows = next;
    endResetModel();
    return;
  }
  rows = next;
  if (!rows.isEmpty())
    emit dataChanged(index(0), index(rows.size() - 1));
}
bool Bridge::validPage(const QString &page) {
  static const QStringList pages{"apps",     "processes",      "performance",
                                 "history",  "startup",        "users",
                                 "services", "system-services"};
  return pages.contains(page);
}
Bridge::Bridge(QObject *p) : QObject(p), m_rows(this) {
  m_page = m_settings.value("page", "apps").toString();
  if (!validPage(m_page))
    m_page = "apps";
  m_interval = m_settings.value("interval", 1000).toInt();
  if (!QList<int>{500, 1000, 2000, 5000}.contains(m_interval))
    m_interval = 1000;
  m_sort = m_settings.value("sort", "cpu").toString();
  m_descending = m_settings.value("descending", true).toBool();
  m_tree = m_settings.value("tree", false).toBool();
  connect(&m_timer, &QTimer::timeout, this, &Bridge::refresh);
  m_timer.start(m_interval);
  m_timeout.setSingleShot(true);
  m_timeout.setInterval(15000);
  connect(&m_timeout, &QTimer::timeout, this, [this] {
    failInspection(
        "Monitoring worker stopped responding. Restart Task Manager.");
    message("Monitoring worker stopped responding. Restart Task Manager.");
    m_worker.kill();
    finish();
  });
  connect(&m_worker, &QProcess::readyReadStandardOutput, this,
          &Bridge::receive);
  connect(&m_worker, &QProcess::started, this, &Bridge::refresh);
  connect(&m_worker, &QProcess::errorOccurred, this,
          [this](QProcess::ProcessError) {
            failInspection("Cannot run monitoring worker: " +
                           m_worker.errorString());
            message("Cannot run monitoring worker: " + m_worker.errorString());
            finish();
          });
  connect(&m_worker, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
          this, [this](int, QProcess::ExitStatus) {
            m_timer.stop();
            failInspection("Monitoring worker exited. Restart Task Manager.");
            message("Monitoring worker exited. Restart Task Manager.");
            finish();
          });
  connect(&m_worker, &QProcess::readyReadStandardError, this,
          [this] { m_worker.readAllStandardError(); });
  QString adjacent =
      QCoreApplication::applicationDirPath() + "/omarchy-task-manager-core";
  QString installed =
      QDir(QCoreApplication::applicationDirPath())
          .absoluteFilePath(
              "../lib/omarchy-task-manager/omarchy-task-manager-core");
  m_worker.setProgram(QFileInfo::exists(adjacent) ? adjacent : installed);
  m_worker.start();
  m_clock.start();
}
Bridge::~Bridge() {
  m_timer.stop();
  m_worker.closeWriteChannel();
  if (!m_worker.waitForFinished(600)) {
    m_worker.terminate();
    if (!m_worker.waitForFinished(300)) {
      m_worker.kill();
      m_worker.waitForFinished(300);
    }
  }
}
void Bridge::message(const QString &s) {
  m_status = s;
  emit statusChanged();
}
void Bridge::finish() {
  m_busy = false;
  m_timeout.stop();
  emit busyChanged();
}
bool Bridge::send(const QVariantMap &v) {
  if (m_busy || m_worker.state() != QProcess::Running)
    return false;
  m_busy = true;
  emit busyChanged();
  m_timeout.start(v.value("verb") == "dump" ? 65000 : 15000);
  m_worker.write(QJsonDocument::fromVariant(v).toJson(QJsonDocument::Compact) +
                 "\n");
  return true;
}
void Bridge::refresh() {
  if (!m_paused && m_visible &&
      send({{"op", "sample"}, {"page", m_page}, {"reset", m_resetSample}}))
    m_resetSample = false;
}
void Bridge::active(bool v) {
  if (!v)
    m_resetSample = true;
  m_visible = v;
  if (v)
    refresh();
}
void Bridge::receive() {
  m_buffer += m_worker.readAllStandardOutput();
  if (m_buffer.size() > 32 * 1024 * 1024) {
    m_worker.kill();
    failInspection("Worker response exceeded limit");
    message("Worker response exceeded limit");
    return;
  }
  while (m_buffer.contains('\n')) {
    auto at = m_buffer.indexOf('\n');
    auto line = m_buffer.left(at);
    m_buffer.remove(0, at + 1);
    QJsonParseError error;
    auto doc = QJsonDocument::fromJson(line, &error);
    finish();
    if (error.error != QJsonParseError::NoError) {
      failInspection("Invalid monitoring response");
      message("Invalid monitoring response");
      continue;
    }
    handleResponse(doc.toVariant().toMap());
  }
}
void Bridge::handleResponse(const QVariantMap &v) {
  auto kind = v.value("kind").toString();
  if (kind == "snapshot") {
    if (m_paused || !m_visible || m_resetSample) {
      refresh(); // Discard a pre-pause response and request a fresh baseline.
      return;
    }
    m_snapshot = v;
    auto sys = v.value("system").toMap();
    if (!sys.value("continuous").toBool())
      m_history.clear();
    auto cpus = sys.value("cpu").toList();
    auto mem = sys.value("memory").toMap();
    QVariantMap historyPoint{
        {"time", m_clock.elapsed()},
        {"cpu",
         cpus.isEmpty() ? QVariant() : cpus.first().toMap().value("usage")},
        {"memory", mem.value("total").toDouble() > 0
                       ? 100 * mem.value("used").toDouble() /
                             mem.value("total").toDouble()
                       : 0}};
    for (const QString &category : {QString("network"), QString("disks")}) {
      for (const auto &device : sys.value(category).toList()) {
        const auto d = device.toMap();
        const QString prefix = category + ":" + d.value("name").toString();
        historyPoint[prefix + ":first"] = d.value("first_rate");
        historyPoint[prefix + ":second"] = d.value("second_rate");
      }
    }
    for (const auto &c : cpus) {
      auto v = c.toMap();
      if (v.value("name") != "cpu")
        historyPoint[v.value("name").toString()] = v.value("usage");
    }
    for (const auto &gpu : sys.value("gpus").toList()) {
      auto g = gpu.toMap();
      historyPoint["gpu:" + g.value("device").toString()] = g.value("usage");
    }
    m_history.append(historyPoint);
    while (m_history.size() > 1 &&
           m_clock.elapsed() -
                   m_history.first().toMap().value("time").toLongLong() >
               60000)
      m_history.removeFirst();
    if (!m_feedback.isValid() || m_feedback.elapsed() > 6000)
      message(v.value("desktop_error").isNull()
                  ? "Live · CPU is % of total capacity"
                  : "Live metrics · " + v.value("desktop_error").toString());
    rebuild();
    emit snapshotChanged();
    emit selectionChanged();
  } else if (kind == "inspection") {
    if (m_inspecting && m_inspectionPending) {
      m_inspection = v.value("data").toMap();
      emit inspectionChanged();
    }
    m_inspectionPending = false;
  } else if (kind == "action") {
    m_feedback.start();
    QStringList out;
    int failed = 0;
    for (auto x : v.value("results").toList()) {
      auto r = x.toMap();
      if (!r.value("ok").toBool())
        failed++;
      out << r.value("message").toString();
    }
    message(QString(failed ? "Some actions failed: " : "Action complete: ") +
            out.join("; "));
  } else {
    m_feedback.start();
    failInspection(v.value("message").toString());
    message(v.value("message").toString());
  }
}

void Bridge::setPage(const QString &s) {
  if (m_page == s)
    return;
  if (!validPage(s))
    return;
  m_rows.replace({});
  m_page = s;
  m_query.clear();
  m_userFilter = -1;
  m_sort = s == "history"                                    ? "cpu_seconds"
           : s == "users" || s == "apps" || s == "processes" ? "cpu"
                                                             : "name";
  m_selected.clear();
  m_settings.setValue("page", s);
  if (m_worker.state() == QProcess::Running)
    QTimer::singleShot(50, this, &Bridge::refresh);
  emit preferencesChanged();
  rebuild();
  emit selectionChanged();
}
void Bridge::setQuery(const QString &s) {
  m_query = s;
  rebuild();
  emit selectionChanged();
  emit preferencesChanged();
}
void Bridge::setSort(const QString &s) {
  m_sort = s;
  m_settings.setValue("sort", s);
  rebuild();
  emit preferencesChanged();
}
void Bridge::setDescending(bool v) {
  m_descending = v;
  m_settings.setValue("descending", v);
  rebuild();
  emit preferencesChanged();
}
void Bridge::setTree(bool v) {
  m_tree = v;
  m_settings.setValue("tree", v);
  rebuild();
  emit preferencesChanged();
}
void Bridge::setPaused(bool v) {
  m_paused = v;
  if (v)
    m_resetSample = true;
  emit preferencesChanged();
  if (!v)
    refresh();
  else
    message("Paused · displayed readings are frozen");
}
void Bridge::setInterval(int v) {
  if (!QList<int>{500, 1000, 2000, 5000}.contains(v))
    return;
  m_interval = v;
  m_timer.setInterval(v);
  m_settings.setValue("interval", v);
  emit preferencesChanged();
}
void Bridge::setSelected(const QString &s) {
  m_selected = s;
  emit selectionChanged();
}
void Bridge::rebuild() {
  QVariantList rows;
  bool apps = m_page == "apps";
  bool processPage = m_page == "processes";
  QVariantList source =
      apps || processPage
          ? m_snapshot.value(apps ? "apps" : "processes").toList()
      : m_page == "history"
          ? m_snapshot.value("usage").toMap().value("rows").toList()
          : (m_snapshot.value("management_page").toString() == m_page
                 ? m_snapshot.value("management").toMap().value("rows").toList()
                 : QVariantList{});
  for (auto item : source) {
    auto v = item.toMap();
    if (processPage) {
      auto id = v.value("id").toMap();
      v["key"] =
          id.value("pid").toString() + ":" + id.value("start").toString();
      v["pid"] = id.value("pid");
      v["targets"] = QVariantList{v.value("id")};
      v["count"] = 1;
      v["io_rate"] =
          (v.value("read_rate").isNull() || v.value("write_rate").isNull())
              ? QVariant()
              : QVariant(v.value("read_rate").toDouble() +
                         v.value("write_rate").toDouble());
    }
    v["depth"] = 0;
    if (processPage && m_userFilter >= 0 &&
        v.value("uid").toInt() != m_userFilter)
      continue;
    if (!m_query.isEmpty() &&
        !(v.value("name").toString() + " " + v.value("command").toString() +
          " " + v.value("pid").toString() + " " + v.value("user").toString() +
          " " + v.value("description").toString() + " " +
          v.value("state").toString())
             .contains(m_query, Qt::CaseInsensitive))
      continue;
    rows.append(v);
  }
  std::stable_sort(
      rows.begin(), rows.end(), [this](const QVariant &a, const QVariant &b) {
        auto x = a.toMap(), y = b.toMap();
        auto vx = x.value(m_sort), vy = y.value(m_sort);
        if (vx.isNull() != vy.isNull())
          return !vx.isNull();
        int c = 0;
        if (m_sort == "name" || m_sort == "user" || m_sort == "state" ||
            m_sort == "sub" || m_sort == "impact")
          c = QString::compare(vx.toString(), vy.toString(),
                               Qt::CaseInsensitive);
        else
          c = (vx.toDouble() > vy.toDouble()) - (vx.toDouble() < vy.toDouble());
        if (c == 0)
          return x.value("key").toString() < y.value("key").toString();
        return m_descending ? c > 0 : c < 0;
      });
  if (processPage && m_tree && m_query.isEmpty()) {
    QHash<int, QVariantMap> all;
    QHash<int, QList<int>> children;
    for (auto r : rows) {
      auto p = r.toMap();
      int pid = p.value("pid").toInt();
      all[pid] = p;
      children[p.value("ppid").toInt()].append(pid);
    }
    QVariantList ordered;
    QSet<int> seen;
    std::function<void(int, int)> visit = [&](int pid, int depth) {
      if (seen.contains(pid) || depth > 256)
        return;
      seen.insert(pid);
      auto p = all[pid];
      p["depth"] = qMin(depth, 12);
      ordered.append(p);
      for (auto c : children[pid])
        visit(c, depth + 1);
    };
    for (auto r : rows) {
      auto p = r.toMap();
      if (!all.contains(p.value("ppid").toInt()))
        visit(p.value("pid").toInt(), 0);
    }
    for (auto r : rows)
      visit(r.toMap().value("pid").toInt(), 0);
    rows = ordered;
  }
  m_rows.replace(rows);
}
QVariantMap Bridge::selection() const {
  for (auto r : m_rows.rows) {
    auto p = r.toMap();
    if (p.value("key").toString() == m_selected)
      return p;
  }
  return {};
}
QVariantMap Bridge::prepareAction(bool force) {
  auto s = selection();
  cancelAction();
  if (m_busy || s.isEmpty() || (m_page != "apps" && m_page != "processes"))
    return {};
  if (s.value("protected").toBool() ||
      s.value("uid").toInt() != m_snapshot.value("uid").toInt()) {
    message("This process cannot be controlled by this user");
    return {};
  }
  auto targets = s.value("targets").toList();
  if (targets.isEmpty())
    return {};
  m_pending = {{"op", "signal"}, {"targets", targets}, {"force", force}};
  QStringList pids;
  for (auto t : targets)
    pids << t.toMap().value("pid").toString();
  return {{"title", (force ? "Force quit " : "Terminate ") +
                        s.value("name").toString() + "?"},
          {"body",
           QString("%1 selected process(es): %2\n\n%3\nNew processes will not "
                   "be added to this action.")
               .arg(targets.size())
               .arg(pids.join(", "))
               .arg(force ? "Unsaved work may be lost. This cannot be undone."
                          : "Request termination with SIGTERM. This does not "
                            "guarantee a save prompt.")}};
}
void Bridge::confirmAction() {
  if (m_pending.isEmpty())
    return;
  if (m_busy) {
    message("Monitor is busy; try the action again");
    cancelAction();
    return;
  }
  send(m_pending);
  cancelAction();
}
void Bridge::cancelAction() { m_pending.clear(); }
void Bridge::windowAction(bool close) {
  auto s = selection();
  auto ws = s.value("windows").toList();
  if (m_busy || ws.isEmpty())
    return;
  // One window per explicit invocation; avoids queues that might close a newly
  // opened window.
  auto w = ws.first().toMap();
  auto targets = s.value("targets").toList();
  QVariant id;
  for (auto t : targets)
    if (t.toMap().value("pid") == w.value("pid")) {
      id = t;
      break;
    }
  if (id.isValid())
    send({{"op", "window"},
          {"id", id},
          {"address", w.value("address")},
          {"close", close}});
}
void Bridge::selectOffset(int offset) {
  int row = -1;
  for (int i = 0; i < m_rows.rows.size(); i++)
    if (m_rows.rows[i].toMap().value("key") == m_selected) {
      row = i;
      break;
    }
  if (!m_rows.rows.isEmpty())
    setSelected(
        m_rows.rows[qBound(0, row + offset, int(m_rows.rows.size() - 1))]
            .toMap()
            .value("key")
            .toString());
}
QString Bridge::bytes(double n) const {
  QStringList units{"B", "KiB", "MiB", "GiB", "TiB"};
  int i = 0;
  while (n >= 1024 && i < 4) {
    n /= 1024;
    i++;
  }
  return QString::number(n, 'f', i ? 1 : 0) + " " + units[i];
}
QString Bridge::percent(const QVariant &v) const {
  return v.isNull() ? "—" : QString::number(v.toDouble(), 'f', 1) + "%";
}
QString Bridge::details() const {
  auto s = selection();
  if (s.isEmpty())
    return "Select an application or process to inspect it.";
  QStringList lines{s.value("name").toString()};
  if (m_page != "apps" && m_page != "processes")
    return QString::fromUtf8(
        QJsonDocument::fromVariant(s).toJson(QJsonDocument::Indented));
  if (m_page == "apps") {
    lines << s.value("note").toString();
    QSet<int> members;
    for (const auto &target : s.value("targets").toList())
      members.insert(target.toMap().value("pid").toInt());
    for (const auto &value : m_snapshot.value("processes").toList()) {
      const auto p = value.toMap();
      const auto id = p.value("id").toMap();
      if (members.contains(id.value("pid").toInt()))
        lines << QString("Process %1: %2")
                     .arg(id.value("pid").toString(),
                          p.value("name").toString());
    }

    for (auto w : s.value("windows").toList())
      lines << "Window: " + w.toMap().value("title").toString();
  } else {
    lines << "PID: " + s.value("pid").toString() +
                 "  •  Parent: " + s.value("ppid").toString() +
                 "  •  User: " + s.value("user").toString() +
                 "  •  State: " + s.value("state").toString();
    lines << s.value("command").toString();
    lines << QString("Threads: %1 · Nice: %2 · CPU time: %3 s · Virtual: %4 · "
                     "GPU: %5")
                 .arg(s.value("threads").toString(), s.value("nice").toString(),
                      s.value("cpu_seconds").toString(),
                      bytes(s.value("virtual_memory").toDouble()),
                      percent(s.value("gpu")));
    lines << "Disk read: " +
                 (s.value("read_rate").isNull()
                      ? "Unavailable"
                      : bytes(s.value("read_rate").toDouble()) + "/s") +
                 "  •  Write: " +
                 (s.value("write_rate").isNull()
                      ? "Unavailable"
                      : bytes(s.value("write_rate").toDouble()) + "/s");
  }
  if (s.value("protected").toBool())
    lines << "Protected desktop/session process";
  return lines.join("\n");
}
QVariant Bridge::preference(const QString &k, const QVariant &v) const {
  const auto value = m_settings.value(k, v);
  if (k == "width" || k == "height") {
    bool ok = false;
    const int n = value.toInt(&ok);
    const int minimum = k == "width" ? 640 : 420;
    return ok && n >= minimum && n <= 8192 ? QVariant(n) : v;
  }
  return value;
}
void Bridge::savePreference(const QString &k, const QVariant &v) {
  if (k == "width" || k == "height" || k == "sidebarCollapsed" ||
      k == "columnWidths")
    m_settings.setValue(k, v);
}

QVariantMap Bridge::prepareManagement(const QVariantMap &request) {
  cancelAction();
  if (m_busy)
    return {};
  auto r = request;
  r["op"] = "manage";
  const auto category = r.value("category").toString();
  auto selected = selection();
  if (category == "restart") {
    if (m_page != "apps" || selected.isEmpty() ||
        selected.value("desktop_file").toString().isEmpty() ||
        selected.value("protected").toBool() ||
        selected.value("uid") != m_snapshot.value("uid"))
      return {};
    r["targets"] = selected.value("targets");
    r["desktop_file"] = selected.value("desktop_file");
  }
  if (category == "process") {
    if (m_page != "processes" || selected.isEmpty() ||
        selected.value("protected").toBool() ||
        selected.value("uid") != m_snapshot.value("uid"))
      return {};
    r["id"] = selected.value("id");
  }
  if (category == "service" || category == "startup") {
    if ((category == "service" && m_page != "services" &&
         m_page != "system-services") ||
        (category == "startup" &&
         (m_page != "startup" || !selected.value("editable").toBool())))
      return {};
    if (selected.isEmpty())
      return {};
    r["key"] = selected.value("key");
    if (category == "service")
      r["scope"] = selected.value("scope");
  }
  if (category == "session") {
    if (m_page != "users" || selected.isEmpty() ||
        selected.value("uid") != m_snapshot.value("uid"))
      return {};
    r["uid"] = selected.value("uid");
    bool found = false;
    for (auto s : selected.value("sessions").toList())
      if (s.toMap().value("session").toString() ==
          r.value("session").toString())
        found = true;
    if (!found)
      return {};
  }
  if (!QStringList{"restart", "process", "service", "startup", "session",
                   "history"}
           .contains(category) ||
      (category == "history" &&
       (m_page != "history" || r.value("verb") != "reset")))
    return {};
  m_pending = r;
  QString verb = r.value("verb").toString();
  QString name = selected.value("name").toString();
  QString body = "Target: " + name + "\n";
  if (category == "process") {
    body += "PID " + selected.value("pid").toString() +
            " · identity checked again before acting.\n";
    if (verb == "dump")
      body += "Create a core dump in a private local folder. It may contain "
              "passwords, documents, and other process memory. Capture pauses "
              "the process and can take up to 60 seconds. Requires gdb and "
              "ptrace permission.";
    if (verb == "nice")
      body += "Set nice to " + r.value("nice").toString() +
              " for existing threads. Increasing priority or restoring a "
              "lowered priority may require permission.";
    if (verb == "affinity")
      body += "Set CPU affinity for existing threads. Choosing fewer CPUs can "
              "slow this process.";
    if (verb == "suspend")
      body += "Pause execution with SIGSTOP. The process may hold resources "
              "while suspended.";
    if (verb == "resume")
      body += "Resume execution with SIGCONT.";
  } else if (category == "restart")
    body += "Terminate this application and its selected processes, then "
            "reopen its desktop launcher. Unsaved work may be lost.";
  else if (category == "session")
    body += "Session " + r.value("session").toString() + "\n" +
            (verb == "logout" ? "All processes in this session will end. "
                                "Unsaved work may be lost."
                              : "Lock this session.");
  else if (category == "startup") {
    verb = r.value("enabled").toBool() ? "Enable startup" : "Disable startup";
    body += "Applies at next login through a per-user desktop-entry override.";
  } else if (category == "history")
    body = "Delete recorded CPU and disk usage history for this monitor?";
  else
    body += "Scope: " + r.value("scope").toString() +
            "\nSystem services follow your system's permissions. Stopping a "
            "service can interrupt other applications.";
  return {{"title", verb + "?"}, {"body", body}};
}
void Bridge::inspect() {
  auto s = selection();
  if (m_busy || m_page != "processes" || s.isEmpty())
    return;
  beginInspection({{"op", "inspect"}, {"id", s.value("id")}},
                  "Loading process details…");
}
void Bridge::beginInspection(const QVariantMap &request,
                             const QString &loading) {
  if (!send(request)) {
    message("Cannot load details while the monitoring worker is unavailable");
    return;
  }
  m_inspecting = m_inspectionPending = true;
  m_inspection = {{"message", loading}};
  emit inspectionChanged();
  emit inspectionRequested();
}
void Bridge::dismissInspection() { m_inspecting = false; }
void Bridge::failInspection(const QString &error) {
  if (!m_inspectionPending)
    return;
  m_inspectionPending = false;
  if (m_inspecting) {
    m_inspection = {{"message", error}};
    emit inspectionChanged();
  }
}
void Bridge::launch(const QString &command) {
  if (command.size() > 16384) {
    message("Command too long");
    return;
  }
  auto args = QProcess::splitCommand(command);
  if (args.isEmpty())
    return;
  auto program = args.takeFirst();
  QProcess child;
  child.setProgram(program);
  child.setArguments(args);
  child.setWorkingDirectory(QDir::homePath());
  if (child.startDetached())
    message("Started: " + program);
  else
    message("Could not start " + program + ": " + child.errorString());
  m_feedback.start();
}
void Bridge::openExecutable() {
  auto s = selection();
  if (m_page != "processes" || s.isEmpty())
    return;
  auto pid = s.value("pid").toInt();
  auto path = QFileInfo(QString("/proc/%1/exe").arg(pid)).symLinkTarget();
  if (path.isEmpty()) {
    message("Executable path unavailable");
    return;
  }
  QDesktopServices::openUrl(
      QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}
void Bridge::copyDetails() {
  if (auto app = qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
    app->clipboard()->setText(details());
}
void Bridge::exportSnapshot() {
  QString dir =
      QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
  if (dir.isEmpty())
    dir = QDir::homePath();
  QDir().mkpath(dir);
  QString path = dir + "/task-manager-" +
                 QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss-zzz") +
                 ".json";
  QSaveFile f(path);
  if (!f.open(QIODevice::WriteOnly) ||
      f.write(QJsonDocument::fromVariant(m_snapshot).toJson()) < 0 ||
      !f.commit())
    message("Could not export snapshot");
  else
    message("Saved snapshot: " + path);
  m_feedback.start();
}
void Bridge::filterUser(int uid) {
  setPage("processes");
  m_userFilter = uid;
  rebuild();
  message("Showing processes for UID " + QString::number(uid) +
          ". Change page to clear.");
}
void Bridge::floatPanel(int width, int height) {
  if (qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE"))
    return;
  // The worker validates that only its own parent GUI can be positioned.
  if (m_busy) {
    QTimer::singleShot(200, this,
                       [this, width, height] { floatPanel(width, height); });
    return;
  }
  send({{"op", "float"}, {"width", width}, {"height", height}});
}

void Bridge::loadLogs() {
  auto s = selection();
  if (m_busy || s.isEmpty() ||
      (m_page != "services" && m_page != "system-services"))
    return;
  beginInspection({{"op", "manage"},
                   {"category", "service"},
                   {"verb", "logs"},
                   {"key", s.value("key")},
                   {"scope", s.value("scope")}},
                  "Loading service journal…");
}

QVariantMap Bridge::prepareTree(bool force) {
  auto info = prepareAction(force);
  if (info.isEmpty() || m_page != "processes") {
    cancelAction();
    return {};
  }
  auto s = selection();
  QSet<int> ids{s.value("pid").toInt()};
  auto all = m_snapshot.value("processes").toList();
  bool changed = true;
  while (changed) {
    changed = false;
    for (const auto &v : all) {
      auto p = v.toMap();
      int pid = p.value("id").toMap().value("pid").toInt();
      if (ids.contains(p.value("ppid").toInt()) && !ids.contains(pid)) {
        ids.insert(pid);
        changed = true;
      }
    }
  }
  QVariantList targets;
  QStringList labels;
  for (const auto &v : all) {
    auto p = v.toMap();
    auto id = p.value("id").toMap();
    if (!ids.contains(id.value("pid").toInt()))
      continue;
    if (p.value("protected").toBool() ||
        p.value("uid") != m_snapshot.value("uid")) {
      cancelAction();
      message("Tree includes a protected process or another user's process");
      return {};
    }
    targets.append(id);
    labels << id.value("pid").toString() + " " + p.value("name").toString();
  }
  m_pending["targets"] = targets;
  info["title"] = "End process tree?";
  info["body"] =
      "Fixed selection of " + QString::number(targets.size()) +
      " processes:\n" + labels.join("\n") +
      "\n\nUnsaved work may be lost. New descendants are not included.";
  return info;
}
