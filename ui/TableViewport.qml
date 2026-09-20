import QtQuick
import QtQuick.Controls

Flickable {
    id: viewport
    property real minimumContentWidth: 0
    default property alias contents: body.data
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.HorizontalFlick
    contentWidth: Math.max(width, minimumContentWidth)
    contentHeight: height
    ScrollBar.horizontal: ScrollBar {
        id: bar
        policy: viewport.contentWidth > viewport.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    }
    data: Item {
        id: body
        width: viewport.contentWidth
        height: Math.max(0, viewport.height - (bar.visible ? bar.height : 0))
    }
}
