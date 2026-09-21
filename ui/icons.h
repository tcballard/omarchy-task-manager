#pragma once
#include <QGuiApplication>
#include <QIcon>
#include <QPainter>
#include <QPalette>
#include <QQuickImageProvider>

class Icons : public QQuickImageProvider {
public:
  Icons() : QQuickImageProvider(QQuickImageProvider::Pixmap) {
    // Some platform themes name an unavailable icon theme without a fallback.
    // Keep the user's theme, but allow packaged application icons to resolve.
    if (QIcon::fallbackThemeName().isEmpty())
      QIcon::setFallbackThemeName("hicolor");
  }
  QPixmap requestPixmap(const QString &id, QSize *size,
                        const QSize &requested) override {
    const QSize s = requested.isValid() ? requested : QSize(32, 32);
    QIcon icon = id == "omarchy-default"
                     ? QIcon(":/ui/omarchy-logo.svg")
                     : (id.startsWith('/') ? QIcon(id) : QIcon::fromTheme(id));
    auto p = icon.pixmap(s);
    if (p.isNull())
      p = QIcon::fromTheme("application-x-executable").pixmap(s);
    if (p.isNull()) {
      // A recognizable application window even when no generic icon is installed.
      p = QPixmap(s);
      p.fill(Qt::transparent);
      QPainter painter(&p);
      painter.setRenderHint(QPainter::Antialiasing);
      painter.scale(s.width() / 32.0, s.height() / 32.0);
      painter.setPen(QPen(QGuiApplication::palette().color(QPalette::WindowText), 2));
      painter.drawRoundedRect(QRectF(4, 5, 24, 22), 2, 2);
      painter.drawLine(QPointF(4, 11), QPointF(28, 11));
      painter.drawPoint(QPointF(8, 8));
    }
    if (size)
      *size = p.size();
    return p;
  }
};
