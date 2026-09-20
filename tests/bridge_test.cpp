#include "bridge.h"
#include <QCoreApplication>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
class BridgeTest : public QObject {
  Q_OBJECT
private slots:
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
    bridge.setQuery(QString::number(QCoreApplication::applicationPid()));
    QVERIFY(bridge.rows()->rowCount() > 0);
    bridge.selectOffset(1);
    QVERIFY(!bridge.selection().isEmpty());
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
    QSignalSpy samples(&bridge, &Bridge::snapshotChanged);
    bridge.setPaused(false);
    QTRY_VERIFY_WITH_TIMEOUT(samples.count() > 0, 8000);
    QVERIFY(!bridge.snapshot()
                 .value("system")
                 .toMap()
                 .value("continuous")
                 .toBool());
    QCOMPARE(bridge.history().size(), 1);
    bridge.active(false);
    QTest::qWait(600);
    samples.clear();
    bridge.active(true);
    QTRY_VERIFY_WITH_TIMEOUT(samples.count() > 0, 8000);
    QVERIFY(!bridge.snapshot()
                 .value("system")
                 .toMap()
                 .value("continuous")
                 .toBool());
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.busy(), 8000);
    samples.clear();
    bridge.refresh();
    QVERIFY(bridge.busy());
    bridge.setPaused(true);
    bridge.setPaused(false);
    QTRY_VERIFY_WITH_TIMEOUT(samples.count() > 0, 8000);
    QVERIFY(!bridge.snapshot()
                 .value("system")
                 .toMap()
                 .value("continuous")
                 .toBool());
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
