import QtQuick
import QtQuick.Controls

ToolButton {
    id: control
    signal resizeRequested(real pixels)
    signal resizeFinished
    signal resetRequested
    clip: false
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.palette.buttonText
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
    rightPadding: 10
    Keys.onLeftPressed: function (event) {
        if (event.modifiers & Qt.ShiftModifier) {
            resizeRequested(width - 8);
            resizeFinished();
        } else
            event.accepted = false;
    }
    Keys.onRightPressed: function (event) {
        if (event.modifiers & Qt.ShiftModifier) {
            resizeRequested(width + 8);
            resizeFinished();
        } else
            event.accepted = false;
    }
    MouseArea {
        objectName: control.objectName + "_resize"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 10
        z: 2
        cursorShape: Qt.SplitHCursor
        preventStealing: true
        hoverEnabled: true
        property real startX: 0
        property real startWidth: 0
        onPressed: function (mouse) {
            startX = mapToItem(null, mouse.x, mouse.y).x;
            startWidth = control.width;
        }
        onPositionChanged: function (mouse) {
            if (pressed)
                control.resizeRequested(startWidth + mapToItem(null, mouse.x, mouse.y).x - startX);
        }
        onReleased: control.resizeFinished()
        onCanceled: control.resizeFinished()
        onDoubleClicked: control.resetRequested()
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.containsMouse || parent.pressed ? 2 : 1
            height: parent.height * 0.55
            color: parent.containsMouse || parent.pressed ? control.palette.highlight : control.palette.mid
        }
        ToolTip.visible: containsMouse && !pressed
        ToolTip.text: "Drag to resize · Double-click to reset widths"
    }
}
