#include "bridge.h"
#include <QGuiApplication>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>
class UiTest : public QObject {
  Q_OBJECT
private slots:
  void themeChangesWhileOpen() {
    const QString theme = qEnvironmentVariable("XDG_STATE_HOME") +
                          "/omarchy/current/theme";
    QVERIFY(QDir().mkpath(theme));
    auto palette = [&](const QByteArray &background) {
      QFile file(theme + "/colors.toml");
      if (!file.open(QIODevice::WriteOnly))
        return false;
      return file.write("background = \"" + background +
                        "\"\nforeground = \"#eeeeee\"\naccent = \"#aabbcc\"\n") > 0;
    };
    QVERIFY(palette("#101010"));
    Bridge backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/ui/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QTRY_COMPARE_WITH_TIMEOUT(window->property("bg").value<QColor>(),
                             QColor("#101010"), 8000);
    QVERIFY(QDir().rename(theme, theme + ".previous"));
    QVERIFY(QDir().mkpath(theme));
    QVERIFY(palette("#fafafa"));
    QTRY_COMPARE_WITH_TIMEOUT(window->property("bg").value<QColor>(),
                             QColor("#fafafa"), 8000);
    QVERIFY(QDir(theme).removeRecursively());
    QVERIFY(QDir(theme + ".previous").removeRecursively());
  }
  void smallPanelAndMalformedTheme() {
    Bridge backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/ui/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QTRY_VERIFY_WITH_TIMEOUT(!backend.snapshot().isEmpty(), 8000);
    backend.setPage("processes");
    window->setProperty("availableScreenWidth", 640);
    window->setProperty("availableScreenHeight", 480);
    window->resize(640, 480);
    window->setProperty("tokens", QVariantMap{{"font.base-size", "broken"},
                                              {"font.body", "Infinity"}});
    QCOMPARE(window->property("baseSize").toDouble(), 12.0);
    QCOMPARE(window->property("layoutScale").toDouble(), 1.0);
    window->setProperty("tokens", QVariantMap{{"font.base-size", 24}});
    QCOMPARE(window->property("layoutScale").toDouble(), 2.0);
    window->setProperty("showOwner", true);
    window->setProperty("showThreads", true);
    auto workspace = window->findChild<QObject *>("workspaceScroll");
    auto table = window->findChild<QQuickItem *>("processTableViewport");
    QVERIFY(workspace && table);
    QTRY_VERIFY(table->property("contentWidth").toDouble() > table->width());
    QVERIFY(workspace->property("contentWidth").toDouble() >= 1700);
    QVERIFY(workspace->property("contentHeight").toDouble() >= 1120);
    const double end =
        table->property("contentWidth").toDouble() - table->width();
    table->setProperty("contentX", end);
    QCOMPARE(table->property("contentX").toDouble(), end);
    auto close = window->findChild<QQuickItem *>("closePanelButton");
    auto scroll = window->findChild<QObject *>("workspaceHorizontalScroll");
    QVERIFY(close && scroll);
    QVERIFY(close->mapToScene(QPointF(close->width(), 0)).x() <= 640);
    QVERIFY(scroll->property("visible").toBool());
    QCOMPARE(window->width(), 640);
    QCOMPARE(window->height(), 480);
    window->setProperty(
        "tokens", QVariantMap{{"font.base-size", -100}, {"font.body", -100}});
    QCOMPARE(window->property("baseSize").toDouble(), 8.0);
    QVERIFY(window->property("layoutScale").toDouble() >= 1.0);
    window->setProperty(
        "tokens", QVariantMap{{"font.base-size", 1e100}, {"font.body", 1e100}});
    QCOMPARE(window->property("baseSize").toDouble(), 32.0);
    QCOMPARE(window->property("layoutScale").toDouble(), 4.0);
    backend.setPage("history");
    auto management =
        window->findChild<QQuickItem *>("managementTableViewport");
    QVERIFY(management);
    QTRY_VERIFY(management->property("contentWidth").toDouble() >=
                management->width());
  }
  void keyboardAndConfirmedAction() {
    QProcess child;
    child.start("sleep", {"30"});
    QVERIFY(child.waitForStarted());
    Bridge backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/ui/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->requestActivate();
    QTRY_VERIFY_WITH_TIMEOUT(!backend.snapshot().isEmpty(), 8000);
    QTest::keyClick(window, Qt::Key_2, Qt::ControlModifier);
    QCOMPARE(backend.page(), QString("processes"));
    QTest::keyClick(window, Qt::Key_F, Qt::ControlModifier);
    auto search = window->findChild<QQuickItem *>("searchField");
    QVERIFY(search);
    QTRY_VERIFY(search->hasActiveFocus());
    backend.setQuery(QString::number(child.processId()));
    QTRY_VERIFY(backend.rows()->rowCount() > 0);
    backend.selectOffset(1);
    QVERIFY(!backend.selection().value("protected").toBool());
    auto dialog = window->findChild<QObject *>("confirmationDialog");
    QVERIFY(dialog);
    QTRY_VERIFY(!backend.busy());
    QVERIFY(QMetaObject::invokeMethod(window, "ask",
                                      Q_ARG(QVariant, QVariant(true))));
    QTRY_VERIFY(dialog->property("visible").toBool());
    QVERIFY(backend.paused());
    // Application shortcuts must not replace the target, stack dialogs, or
    // change wasPaused while a confirmation is visible.
    QTest::keyClick(window, Qt::Key_3, Qt::ControlModifier);
    QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
    QTest::keyClick(window, Qt::Key_Delete);
    QCOMPARE(backend.page(), QString("processes"));
    QVERIFY(dialog->property("visible").toBool());
    QVERIFY(QMetaObject::invokeMethod(window, "ask",
                                      Q_ARG(QVariant, QVariant(false))));
    window->setProperty(
        "actionInfo",
        QVariantMap{{"title", "<b>literal title</b>"},
                    {"body", "<img src='file:///no-such-image'>literal body"}});
    auto body = window->findChild<QObject *>("confirmationBody");
    QVERIFY(body);
    QCOMPARE(body->property("textFormat").toInt(), 0); // QQuickText::PlainText
    QCOMPARE(body->property("text").toString(),
             QString("<img src='file:///no-such-image'>literal body"));
    QMetaObject::invokeMethod(dialog, "reject");
    QTRY_VERIFY(!dialog->property("visible").toBool());
    QCOMPARE(child.state(), QProcess::Running);
    QVERIFY(!backend.paused());
    QTRY_VERIFY(!backend.busy());
    QVERIFY(QMetaObject::invokeMethod(window, "ask",
                                      Q_ARG(QVariant, QVariant(true))));
    QTRY_VERIFY(dialog->property("visible").toBool());
    QMetaObject::invokeMethod(dialog, "accept");
    QTRY_COMPARE_WITH_TIMEOUT(child.state(), QProcess::NotRunning, 5000);
    QTest::keyClick(window, Qt::Key_3, Qt::ControlModifier);
    QCOMPARE(backend.page(), QString("performance"));
    QTest::qWait(100);
    for (const auto &page :
         {"history", "startup", "users", "services", "system-services", "apps",
          "processes", "performance"}) {
      qInfo() << "Checking page" << page;
      backend.setPage(page);
      QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 15000);
      backend.refresh();
      QTRY_COMPARE_WITH_TIMEOUT(
          backend.snapshot().value("management_page").toString(), QString(page),
          15000);
      QTest::qWait(50);
      auto status = window->findChild<QQuickItem *>("statusLabel");
      QVERIFY(status && status->mapToScene(QPointF(0, status->height())).y() <=
                            window->height());
    }
    QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
    auto command = window->findChild<QQuickItem *>("newTaskCommand");
    QVERIFY(command);
    QTRY_VERIFY(command->hasActiveFocus());
    QTest::keyClick(window, Qt::Key_Escape);

    for (const auto &name : {"versionLabel", "statusLabel"}) {
      auto item = window->findChild<QQuickItem *>(name);
      QVERIFY(item);
      const auto pos = item->mapToScene(QPointF(0, item->height()));
      QVERIFY2(pos.y() <= window->height(),
               qPrintable(QString("%1 bottom %2 exceeds window %3")
                              .arg(name)
                              .arg(pos.y())
                              .arg(window->height())));
    }
  }
};
int main(int argc, char **argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  qputenv("QT_QUICK_BACKEND", "software");
  QTemporaryDir config;
  qputenv("XDG_CONFIG_HOME", config.path().toUtf8());
  qputenv("XDG_STATE_HOME", config.path().toUtf8());
  QGuiApplication app(argc, argv);
  app.setOrganizationName("task-manager-tests");
  app.setApplicationName("ui");
  qmlRegisterUncreatableType<Rows>("TaskManager", 1, 0, "Rows",
                                   "Backend owned");
  UiTest test;
  return QTest::qExec(&test, argc, argv);
}
#include "ui_test.moc"
