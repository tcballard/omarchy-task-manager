#include "icons.h"
#include <QDir>
#include <QFile>
#include <QImage>
#include <QSet>
#include <QTemporaryDir>
#include <QTextStream>
#include <cstdio>

// Ordinary SVGs only: this is a rendering regression, not a CVE reproducer.
int main(int argc, char **argv) {
  QGuiApplication app(argc, argv);
  QTemporaryDir temp;
  if (!temp.isValid()) return 1;
  const QString theme = temp.path() + "/tm-test";
  if (!QDir().mkpath(theme + "/scalable/apps")) return 1;
  auto write = [](const QString &path, const QByteArray &bytes) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
  };
  if (!write(theme + "/index.theme",
             "[Icon Theme]\nName=TM test\nDirectories=scalable/apps\n"
             "[scalable/apps]\nSize=32\nType=Scalable\nMinSize=16\nMaxSize=256\nContext=Applications\n") ||
      !write(temp.path() + "/external.svg",
             "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32'><rect width='32' height='32' fill='#cc2244'/></svg>") ||
      !write(theme + "/scalable/apps/tm-theme.svg",
             "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32'><rect width='32' height='32' fill='#22bb66'/></svg>")) return 1;
  QIcon::setThemeSearchPaths({temp.path()});
  QIcon::setThemeName("tm-test");
  Icons icons;
  for (const QSize size : {QSize(16, 16), QSize(32, 32), QSize(64, 64)}) {
    for (bool themed : {false, true}) {
      QSize actual;
      const QPixmap pixmap = icons.requestPixmap(
          themed ? "tm-theme" : temp.path() + "/external.svg", &actual, size);
      const QImage image = pixmap.toImage();
      const QColor expected(themed ? "#22bb66" : "#cc2244");
      if (actual != size || image.isNull() ||
          image.pixelColor(image.width() / 2, image.height() / 2) != expected) {
        std::fprintf(stderr, "SVG pixel/size check failed (%s, %d)\n",
                     themed ? "theme" : "absolute", size.width());
        return 1;
      }
    }
  }
  QTextStream out(stdout);
  out << "ICON_RENDER_RESULT=pass\nQT_RUNTIME=" << qVersion() << '\n';
  // Identify the files actually mapped by this process, including plugin overrides.
  QFile maps("/proc/self/maps");
  if (maps.open(QIODevice::ReadOnly)) {
    QSet<QString> paths;
    const auto lines = maps.readAll().split('\n');
    for (const QByteArray &bytes : lines) {
      const QString line = QString::fromUtf8(bytes).trimmed();
      const qsizetype start = line.indexOf('/');
      if (start < 0) continue;
      const QString path = line.mid(start);
      if (path.contains("/libQt6Svg.so") || path.endsWith("/libqsvgicon.so") ||
          path.endsWith("/libqsvg.so")) paths.insert(path);
    }
    for (const QString &path : paths) out << "QT_SVG_RUNTIME_FILE=" << path << '\n';
  }
  return 0;
}
