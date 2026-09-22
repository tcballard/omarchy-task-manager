#include "bridge.h"
#include "icons.h"
#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>
#include <cstdio>
int main(int argc, char **argv) {
  QGuiApplication app(argc, argv);
  app.setApplicationName("omarchy-task-manager");
  app.setOrganizationName("tcballard");
  app.setApplicationVersion("0.0.4");
  app.setDesktopFileName("io.github.tcballard.TaskManager");
  const QString runtime =
      QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
  QDir().mkpath(runtime);
  const QString socket = runtime + "/io.github.tcballard.TaskManager";
  QLockFile lock(socket + ".lock");
  if (!lock.tryLock(0)) {
    QLocalSocket client;
    client.connectToServer(socket);
    if (client.waitForConnected(1000)) {
      client.write("activate\n");
      client.waitForBytesWritten(500);
      return 0;
    }
    std::fprintf(stderr, "Task Manager is already starting or running\n");
    return 1;
  }
  QLocalServer server;
  server.setSocketOptions(QLocalServer::UserAccessOption);
  QLocalServer::removeServer(socket);
  if (!server.listen(socket)) {
    std::fprintf(stderr,
                 "Window activation unavailable: local sockets are blocked\n");
  }
  qmlRegisterUncreatableType<Rows>("TaskManager", 1, 0, "Rows",
                                   "Owned by backend");
  Bridge bridge;
  int pageArg = app.arguments().indexOf("--page");
  if (pageArg >= 0 && pageArg + 1 < app.arguments().size()) {
    QString page = app.arguments()[pageArg + 1];
    bridge.setPage(page);
  }
  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("backend", &bridge);
  engine.addImageProvider("icons", new Icons);
  engine.load(QUrl("qrc:/ui/Main.qml"));
  if (engine.rootObjects().isEmpty())
    return 1;
  auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
  if (window)
    QTimer::singleShot(700, &bridge, [&bridge, window] {
      // The compositor can tile the first frame before we request floating.
      // Use the user's requested size, not that temporary tile's dimensions.
      bridge.floatPanel(window->property("preferredPanelWidth").toInt(),
                        window->property("preferredPanelHeight").toInt());
    });
  QObject::connect(&server, &QLocalServer::newConnection, &app, [&] {
    while (auto c = server.nextPendingConnection()) {
      c->disconnectFromServer();
      c->deleteLater();
    }
    if (window) {
      window->show();
      window->raise();
      window->requestActivate();
    }
  });
  if (app.arguments().contains("--smoke")) {
    QTimer::singleShot(3000, &app, [&] {
      int i = app.arguments().indexOf("--screenshot");
      if (i >= 0 && i + 1 < app.arguments().size() && window)
        window->grabWindow().save(app.arguments()[i + 1]);
      app.exit(bridge.snapshot().isEmpty() ? 2 : 0);
    });
  }
  return app.exec();
}
