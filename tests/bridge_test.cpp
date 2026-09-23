#include "bridge.h"
#include <QCoreApplication>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <memory>
#include <signal.h>
class BridgeTest : public QObject {
  Q_OBJECT
private slots:
  void shutdownDoesNotPublish_data() {
    QTest::addColumn<bool>("inFlight");
    QTest::addColumn<bool>("stopped");
    QTest::newRow("idle") << false << false;
    QTest::newRow("sample-in-flight") << true << false;
    QTest::newRow("stopped-worker") << true << true;
  }
  void shutdownDoesNotPublish() {
    QFETCH(bool, inFlight);
    QFETCH(bool, stopped);
    auto bridge = std::make_unique<Bridge>();
    QTRY_VERIFY_WITH_TIMEOUT(!bridge->snapshot().isEmpty(), 8000);
    bridge->m_timer.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!bridge->busy(), 8000);
    // Stop only the disposable worker owned by this bridge, forcing shutdown
    // through terminate/kill rather than the normal stdin-EOF exit.
    if (stopped) {
      const auto workerPid = bridge->m_worker.processId();
      QVERIFY(workerPid > 0);
      QCOMPARE(::kill(workerPid, SIGSTOP), 0);
    }
    if (inFlight) {
      bridge->refresh();
      QVERIFY(bridge->busy());
    }
    QSignalSpy snapshots(bridge.get(), &Bridge::snapshotChanged);
    QSignalSpy statuses(bridge.get(), &Bridge::statusChanged);
    QSignalSpy busy(bridge.get(), &Bridge::busyChanged);
    // Closing the app must not publish late samples or worker-exit errors while
    // its bridge and UI are being destroyed. Spies outlive the bridge on purpose.
    bridge.reset();
    QCOMPARE(snapshots.count(), 0);
    QCOMPARE(statuses.count(), 0);
    QCOMPARE(busy.count(), 0);
  }
  void inspectionErrorsAndDismissal() {
    Bridge bridge;
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.snapshot().isEmpty(), 8000);
    bridge.setPaused(true);
    QTRY_VERIFY(!bridge.busy());
    QSignalSpy opened(&bridge, &Bridge::inspectionRequested);
    bridge.beginInspection(
        {{"op", "inspect"}, {"id", QVariantMap{{"pid", -1}, {"start", 0}}}},
        "Loading");
    QCOMPARE(opened.count(), 1);
    QTRY_VERIFY(!bridge.busy());
    QVERIFY(bridge.inspection().value("message").toString() != "Loading");
    bridge.beginInspection(
        {{"op", "inspect"}, {"id", QVariantMap{{"pid", -1}, {"start", 0}}}},
        "Loading");
    bridge.dismissInspection();
    QTRY_VERIFY(!bridge.busy());
    QCOMPARE(opened.count(), 2);
    // A late successful reply cannot update or reopen dismissed details.
    bridge.m_inspectionPending = true;
    bridge.handleResponse(
        {{"kind", "inspection"}, {"data", QVariantMap{{"logs", "late"}}}});
    QVERIFY(!bridge.inspection().contains("logs"));
    QCOMPARE(opened.count(), 2);
    bridge.m_inspecting = bridge.m_inspectionPending = true;
    bridge.failInspection("Monitoring worker exited");
    QCOMPARE(bridge.inspection().value("message").toString(),
             QString("Monitoring worker exited"));
  }
  void modelResize() {
    Rows rows;
    rows.replace({QVariantMap{{"key", "a"}}, QVariantMap{{"key", "b"}}});
    QCOMPARE(rows.rowCount(), 2);
    rows.replace({QVariantMap{{"key", "b"}}});
    QCOMPARE(rows.rowCount(), 1);
    QCOMPARE(rows.data(rows.index(0), Qt::UserRole + 1)
                 .toMap()
                 .value("key")
                 .toString(),
             QString("b"));
    rows.replace({});
    QCOMPARE(rows.rowCount(), 0);
  }
  void liveWorkerSelectionAndPause() {
    Bridge bridge;
    bridge.savePreference("width", "broken");
    QCOMPARE(bridge.preference("width", 1120).toInt(), 1120);
    bridge.savePreference("width", 1200);
    QCOMPARE(bridge.preference("width", 1120).toInt(), 1200);
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.snapshot().isEmpty(), 8000);
    bridge.setPage("processes");
    QVERIFY(bridge.rows()->rowCount() > 0);
    const auto ownPid = QCoreApplication::applicationPid();
    // Search is substring-based across PID, command and other fields. A
    // matching first row is not necessarily this test process. Keep a decoy
    // ahead of it so this selection check cannot pass by lucky PID allocation.
    auto processes = bridge.m_snapshot.value("processes").toList();
    processes.append(QVariantMap{
        {"id", QVariantMap{{"pid", -1}, {"start", 1}}},
        {"name", "PID search decoy"},
        {"command", QString::number(ownPid)},
        {"cpu", 1000000.0},
        {"protected", false}});
    bridge.m_snapshot["processes"] = processes;
    bridge.setQuery(QString::number(ownPid));
    QVERIFY(bridge.rows()->rowCount() > 1);
    QCOMPARE(bridge.rows()->rows.first().toMap().value("pid").toInt(), -1);
    int ownRow = -1;
    for (int row = 0; row < bridge.rows()->rowCount(); ++row) {
      if (bridge.rows()->rows[row].toMap().value("pid").toLongLong() == ownPid) {
        ownRow = row;
        break;
      }
    }
    QVERIFY(ownRow >= 0);
    bridge.selectOffset(ownRow + 1);
    QVERIFY(!bridge.selection().isEmpty());
    QCOMPARE(bridge.selection().value("pid").toLongLong(), ownPid);
    const auto key = bridge.selected();
    bridge.setSort("memory");
    bridge.setDescending(false);
    QCOMPARE(bridge.selected(), key);
    QVERIFY(bridge.selection().value("protected").toBool());
    QVERIFY(bridge.prepareAction(true).isEmpty());
    bridge.setQuery("__does_not_exist_123456789__");
    QCOMPARE(bridge.rows()->rowCount(), 0);
    QVERIFY(bridge.selection().isEmpty());
    bridge.setQuery("");
    bridge.setTree(true);
    QVERIFY(bridge.rows()->rowCount() > 0);
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 8000);
    bridge.setPaused(true);
    const auto before = bridge.history().size();
    QTest::qWait(1100);
    QCOMPARE(bridge.history().size(), before);
    // Capture at emission: QTRY processes events, so another timer sample can
    // replace bridge.snapshot() before the waiting assertion runs.
    QVariantList samples;
    QList<int> historySizes;
    QObject sampleObserver; // Disconnect before the captured lists are destroyed.
    connect(&bridge, &Bridge::snapshotChanged, &sampleObserver, [&] {
      samples.append(bridge.snapshot());
      historySizes.append(bridge.history().size());
    });
    bridge.setPaused(false);
    QTRY_VERIFY_WITH_TIMEOUT(samples.count() > 0, 8000);
    QVERIFY(!samples.first().toMap()
                 .value("system")
                 .toMap()
                 .value("continuous")
                 .toBool());
    QCOMPARE(historySizes.first(), 1);
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 8000);
    samples.clear();
    historySizes.clear();
    bridge.refresh();
    QVERIFY(bridge.busy());
    bridge.setPaused(true);
    bridge.setPaused(false);
    QTRY_VERIFY_WITH_TIMEOUT(samples.count() > 0, 8000);
    QVERIFY(!samples.first().toMap()
                 .value("system")
                 .toMap()
                 .value("continuous")
                 .toBool());
    QCOMPARE(historySizes.first(), 1);
    // Keep automatic refresh enabled. The baseline must be followed by a
    // continuous sample; inspecting only the latest snapshot misses this order.
    QTRY_VERIFY_WITH_TIMEOUT(samples.count() >= 2, 8000);
    QVERIFY(samples.at(1).toMap().value("system").toMap()
                .value("continuous").toBool());
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 8000);
    QVERIFY(bridge.prepareManagement({{"category", "startup"}}).isEmpty());
    QVERIFY(
        bridge.prepareManagement({{"category", "service"}, {"verb", "stop"}})
            .isEmpty());
    QVERIFY(
        bridge.prepareManagement({{"category", "history"}, {"verb", "reset"}})
            .isEmpty());
    bridge.setPage("not-a-page");
    QCOMPARE(bridge.page(), QString("processes"));
  }
};
int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  QTemporaryDir config;
  qputenv("XDG_CONFIG_HOME", config.path().toUtf8());
  qputenv("XDG_STATE_HOME", config.path().toUtf8());
  app.setOrganizationName("task-manager-tests");
  app.setApplicationName("bridge");
  BridgeTest test;
  return QTest::qExec(&test, argc, argv);
}
#include "bridge_test.moc"
