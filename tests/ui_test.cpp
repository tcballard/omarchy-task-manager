#include "bridge.h"
#include "icons.h"
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
static QQuickItem *visualItem(QQuickItem *root, const QString &name) {
  if (root->objectName() == name) return root;
  for (auto child : root->childItems())
    if (auto found = visualItem(child, name)) return found;
  return nullptr;
}
class UiTest : public QObject {
  Q_OBJECT
private slots:
  void iconsWithMissingDesktopTheme() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto paths = QIcon::themeSearchPaths();
    const auto theme = QIcon::themeName();
    const auto fallback = QIcon::fallbackThemeName();
    const QString root = directory.path() + "/hicolor";
    QVERIFY(QDir().mkpath(root + "/32x32/apps"));
    QFile index(root + "/index.theme");
    QVERIFY(index.open(QIODevice::WriteOnly));
    index.write("[Icon Theme]\nName=Hicolor\nDirectories=32x32/apps\n"
                "[32x32/apps]\nSize=32\nType=Fixed\nContext=Applications\n");
    index.close();
    QPixmap fixture(32, 32);
    fixture.fill(QColor("#12ab34"));
    const QString file = root + "/32x32/apps/fixture.png";
    QVERIFY(fixture.save(file));
    QIcon::setThemeSearchPaths({directory.path()});
    QIcon::setThemeName("missing-desktop-theme");
    QIcon::setFallbackThemeName("");
    Icons icons;
    QSize size;
    auto brand = icons.requestPixmap("omarchy-default", &size, QSize(32, 32)).toImage();
    QCOMPARE(size, QSize(32, 32));
    QCOMPARE(brand.pixelColor(1, 1), QColor("#9ece6a"));
    QCOMPARE(brand.pixelColor(16, 16).alpha(), 0);
    for (const auto &id : {QString("fixture"), file}) {
      auto rendered = icons.requestPixmap(id, &size, QSize(32, 32));
      QCOMPARE(size, QSize(32, 32));
      QCOMPARE(rendered.toImage().pixelColor(16, 16), QColor("#12ab34"));
    }
    for (const auto &id : {QString("missing-app"), directory.path() + "/missing.png"}) {
      auto rendered = icons.requestPixmap(id, &size, QSize(32, 32)).toImage();
      QCOMPARE(rendered.pixelColor(0, 0).alpha(), 0);
      QVERIFY(rendered.pixelColor(4, 16).alpha() > 0);
    }
    QIcon::setThemeSearchPaths(paths);
    QIcon::setThemeName(theme);
    QIcon::setFallbackThemeName(fallback);
  }
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
    engine.addImageProvider("icons", new Icons);
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
  void backgroundServiceSetting() {
    if (qEnvironmentVariable("TASK_MANAGER_LIVE_BACKGROUND") != "1")
      QSKIP("Requires the disposable CI user and installed collector fixture");
    BackgroundMonitor monitor;
    monitor.setEnabled(true);
    QTRY_VERIFY_WITH_TIMEOUT(!monitor.busy(), 15000);
    QVERIFY2(monitor.status().startsWith("Background collection enabled"), qPrintable(monitor.status()));
    QVERIFY(monitor.enabled());
    const auto cache = qEnvironmentVariable("XDG_RUNTIME_DIR") + "/omarchy-task-manager-monitor/history.json";
    QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(cache), 5000);
    monitor.setEnabled(false);
    QTRY_VERIFY_WITH_TIMEOUT(!monitor.busy(), 15000);
    QVERIFY2(!monitor.enabled(), qPrintable(monitor.status()));
    QVERIFY(!QFile::exists(cache));
    BackgroundMonitor reopened;
    QVERIFY(!reopened.enabled());
    reopened.initialize();
    QVERIFY(!reopened.busy());
    const auto bus = qgetenv("DBUS_SESSION_BUS_ADDRESS");
    const auto runtime = qgetenv("XDG_RUNTIME_DIR");
    // systemctl can use the private user-manager socket instead of the bus.
    qputenv("XDG_RUNTIME_DIR", "/nonexistent-task-manager-test-runtime");
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-task-manager-test-bus");
    reopened.setEnabled(true);
    QTRY_VERIFY_WITH_TIMEOUT(!reopened.busy(), 15000);
    QVERIFY(!reopened.enabled());
    QVERIFY(reopened.status().contains("could not be changed"));
    qputenv("DBUS_SESSION_BUS_ADDRESS", bus);
    qputenv("XDG_RUNTIME_DIR", runtime);
  }
  void restoredBackgroundHistory() {
    QTemporaryDir runtime;
    QVERIFY(runtime.isValid());
    const auto previousRuntime = qgetenv("XDG_RUNTIME_DIR");
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
    QProcess collector;
    collector.start(QCoreApplication::applicationDirPath() + "/omarchy-task-manager-core", {"--monitor"});
    QVERIFY(collector.waitForStarted());
    QTest::qWait(2400);
    {
      Bridge backend;
      QTRY_VERIFY_WITH_TIMEOUT(backend.history().size() >= 3, 8000);
      QVERIFY(backend.history().first().toMap().value("time").toLongLong() < 0);
      backend.setPaused(true);
      const auto frozen = backend.history();
      QTest::qWait(1100);
      QCOMPARE(backend.history(), frozen);
      backend.setPaused(false);
      QTRY_VERIFY_WITH_TIMEOUT(backend.history() != frozen, 8000);
      QVERIFY(backend.history().first().toMap().value("time").toLongLong() >= 0);
    }
    QVERIFY(collector.state() == QProcess::Running);
    {
      Bridge reopened;
      QTRY_VERIFY_WITH_TIMEOUT(reopened.history().size() >= 3, 8000);
      QVERIFY(reopened.history().first().toMap().value("time").toLongLong() < 0);
    }
    collector.terminate();
    QVERIFY(collector.waitForFinished(3000));
    if (previousRuntime.isNull()) qunsetenv("XDG_RUNTIME_DIR");
    else qputenv("XDG_RUNTIME_DIR", previousRuntime);
  }
  void backgroundHistory_data() {
    QTest::addColumn<bool>("minimized");
    QTest::newRow("hidden") << false;
    QTest::newRow("minimized") << true;
  }
  void backgroundHistory() {
    QFETCH(bool, minimized);
    Bridge backend;
    backend.setInterval(500);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.addImageProvider("icons", new Icons);
    engine.load(QUrl("qrc:/ui/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->setProperty("pinned", true);
    QTRY_VERIFY_WITH_TIMEOUT(backend.history().size() >= 2, 8000);
    const auto firstTime = backend.history().first().toMap().value("time");
    if (minimized)
      window->showMinimized();
    else
      window->hide();
    QCOMPARE(window->visibility(), minimized ? QWindow::Minimized : QWindow::Hidden);
    // Require multiple automatic samples, so an in-flight reply cannot pass.
    const auto before = backend.history().size();
    QTRY_VERIFY_WITH_TIMEOUT(backend.history().size() >= before + 2, 8000);
    QCOMPARE(backend.history().first().toMap().value("time"), firstTime);
    window->showNormal();
    const auto returning = backend.history().size();
    QTRY_VERIFY_WITH_TIMEOUT(backend.history().size() >= returning + 2, 8000);
    QCOMPARE(backend.history().first().toMap().value("time"), firstTime);
    QVERIFY(backend.snapshot().value("system").toMap().value("continuous").toBool());

    // Manual pause remains authoritative across visibility changes.
    backend.setPaused(true);
    QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 8000);
    const auto pausedHistory = backend.history();
    window->hide();
    QTest::qWait(1100);
    QCOMPARE(backend.history(), pausedHistory);
    window->showNormal();
    QTest::qWait(600);
    QCOMPARE(backend.history(), pausedHistory);
    QVERIFY(backend.paused());
    backend.setPaused(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend.history() != pausedHistory, 8000);
    QVERIFY(backend.history().first().toMap().value("time") != firstTime);
  }
  void summaryFindsApplications() {
    Bridge backend;
    // Previous tests may have saved another page; explicitly exercise Summary.
    backend.setPage("summary");
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.addImageProvider("icons", new Icons);
    engine.load(QUrl("qrc:/ui/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QTRY_VERIFY_WITH_TIMEOUT(!backend.snapshot().isEmpty(), 8000);
    auto summary = window->findChild<QQuickItem *>("summaryView");
    auto all = window->findChild<QQuickItem *>("summaryViewAllButton");
    QVERIFY(summary && all);
    QVERIFY(summary->isVisible());
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier,
                      all->mapToScene(QPointF(all->width() / 2,
                                               all->height() / 2)).toPoint());
    QCOMPARE(backend.page(), QString("apps"));
    auto search = window->findChild<QQuickItem *>("searchField");
    QVERIFY(search);
    QTRY_VERIFY(search->hasActiveFocus());
    QTest::keyClick(window, Qt::Key_0, Qt::ControlModifier);
    QCOMPARE(backend.page(), QString("summary"));
  }
  void smallPanelAndMalformedTheme() {
    Bridge backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.addImageProvider("icons", new Icons);
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
    QCOMPARE(workspace->property("contentWidth").toDouble(), 640.0);
    QVERIFY(workspace->property("contentHeight").toDouble() <= 480);
    const double end =
        table->property("contentWidth").toDouble() - table->width();
    table->setProperty("contentX", end);
    QCOMPARE(table->property("contentX").toDouble(), end);
    auto close = window->findChild<QQuickItem *>("closePanelButton");
    QVERIFY(close);
    QVERIFY(close->mapToScene(QPointF(close->width(), 0)).x() <= 640);
    QVERIFY(!window->findChild<QObject *>("workspaceHorizontalScroll"));
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
  void sidebarAndResizableColumns() {
    Bridge backend;
    backend.setPage("apps");
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.addImageProvider("icons", new Icons);
    engine.load(QUrl("qrc:/ui/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->setProperty("availableScreenWidth", 1400);
    window->setProperty("availableScreenHeight", 1000);
    window->resize(1120, 760);
    window->setProperty("sidebarCollapsed", false);
    QTRY_VERIFY_WITH_TIMEOUT(!backend.snapshot().isEmpty(), 8000);
    auto sidebar = window->findChild<QQuickItem *>("sidebar");
    auto toggle = window->findChild<QQuickItem *>("sidebarToggle");
    auto table = window->findChild<QQuickItem *>("processTableViewport");
    QVERIFY(sidebar && toggle && table);
    QTRY_VERIFY(sidebar->width() > 100);
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier,
                     toggle->mapToScene(QPointF(toggle->width()/2, toggle->height()/2)).toPoint());
    QTRY_COMPARE(sidebar->width(), 56.0);
    QVERIFY(backend.preference("sidebarCollapsed", false).toBool());
    QTRY_COMPARE(table->property("contentWidth").toDouble(), table->width());
    auto header = visualItem(window->contentItem(), "columnHeader_memory");
    auto handle = visualItem(window->contentItem(), "columnHeader_memory_resize");
    QVERIFY(header && handle);
    const double original = header->width();
    const auto sort = backend.sort();
    const auto start = handle->mapToScene(QPointF(3, handle->height()/2)).toPoint();
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
    QTest::mouseMove(window, start + QPoint(60, 0), 30);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, start + QPoint(60, 0));
    QTRY_VERIFY(header->width() >= original + 50);
    QCOMPARE(backend.sort(), sort); // Dragging a divider must not sort the list.
    QVERIFY(backend.preference("columnWidths", "").toString().contains("memory"));
    QVERIFY(QMetaObject::invokeMethod(window, "resetColumns"));
    QTRY_COMPARE(header->width(), original);
    for (const QSize size : {QSize(640, 480), QSize(850, 560), QSize(1120, 760)}) {
      window->resize(size);
      QTest::qWait(50);
      auto content = window->findChild<QQuickItem *>("mainContent");
      auto close = window->findChild<QQuickItem *>("closePanelButton");
      auto actions = window->findChild<QQuickItem *>("processActions");
      QVERIFY(content && close && actions);
      QVERIFY(content->mapToScene(QPointF(content->width(), 0)).x() <= size.width());
      QVERIFY(close->mapToScene(QPointF(close->width(), 0)).x() <= size.width());
      QVERIFY(actions->mapToScene(QPointF(0, actions->height())).y() <= size.height());
      QCOMPARE(table->property("contentWidth").toDouble(), table->width());
    }
    backend.savePreference("sidebarCollapsed", false);
  }
  void keyboardAndConfirmedAction() {
    QProcess child;
    child.start("sleep", {"30"});
    QVERIFY(child.waitForStarted());
    Bridge backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.addImageProvider("icons", new Icons);
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
  if (qEnvironmentVariable("TASK_MANAGER_LIVE_BACKGROUND") != "1")
    qputenv("XDG_CONFIG_HOME", config.path().toUtf8());
  qputenv("XDG_STATE_HOME", config.path().toUtf8());
  QGuiApplication app(argc, argv);
  app.setOrganizationName("task-manager-tests");
  app.setApplicationName("ui");
  qmlRegisterUncreatableType<BackgroundMonitor>("TaskManager", 1, 0, "BackgroundMonitor", "Owned by backend");
  qmlRegisterUncreatableType<Rows>("TaskManager", 1, 0, "Rows",
                                   "Backend owned");
  UiTest test;
  return QTest::qExec(&test, argc, argv);
}
#include "ui_test.moc"
