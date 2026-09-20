import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

Button {
    id: control
    property var tokens: backend.snapshot.theme ? (backend.snapshot.theme.shell || ({})) : ({})
    function n(key, fallback) {
        return Theme.number(tokens, key, fallback, 0, key.indexOf("alpha") >= 0 ? 1 : 8);
    }
    implicitHeight: Math.max(28, font.pixelSize + 14)
    implicitWidth: Math.max(72, contentItem.implicitWidth + 20)
    padding: 6
    horizontalPadding: 10
    hoverEnabled: true
    contentItem: Text {
        textFormat: Text.PlainText
        text: control.text
        font: control.font
        color: control.palette.buttonText
        opacity: control.enabled ? 1 : 0.35
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        color: Qt.rgba(control.palette.buttonText.r, control.palette.buttonText.g, control.palette.buttonText.b, control.down ? control.n("controls.pressed-fill-alpha", 0.22) : control.checked ? control.n("controls.selected-fill-alpha", 0.18) : control.hovered || control.activeFocus ? control.n("controls.hover-cursor-fill-alpha", 0.08) : control.n("controls.normal-fill-alpha", 0.04))
        border.width: control.checked ? control.n("controls.selected-border-width", 0) : control.n("controls.normal-border-width", 1)
        border.color: control.activeFocus ? control.palette.highlight : Qt.rgba(control.palette.buttonText.r, control.palette.buttonText.g, control.palette.buttonText.b, 0.25)
        opacity: control.enabled ? 1 : 0.4
    }
}
