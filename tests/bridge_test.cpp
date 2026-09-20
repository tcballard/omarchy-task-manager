#include "bridge.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QTest>
class BridgeTest : public QObject {
  Q_OBJECT
private slots:
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
