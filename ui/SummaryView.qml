import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: summary
    property var snapshot: ({})
    property var history: []
    property color fg: "white"
    property color accent: "#8cb4fa"
    property color muted: "#aaaaaa"
    property color panel: "#20242a"
    property color line: "#40444a"
    property real textScale: 1
    signal openApplications()
    signal openPerformance()
    signal selectApplication(string key)

    property var system: snapshot.system || ({})
    property var memory: system.memory || ({})
    property var applications: {
        var rows = (snapshot.apps || []).slice();
        rows.sort(function(a, b) { return (b.cpu || 0) - (a.cpu || 0); });
        return rows.slice(0, 8);
    }
    function percent(value) { return backend.percent(value); }
    function bytes(value) { return backend.bytes(value); }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * summary.textScale
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 36
            PlainLabel {
                Layout.fillWidth: true
                text: "Running applications"
                font.bold: true
                font.pixelSize: 15 * summary.textScale
                color: summary.fg
                elide: Text.ElideRight
            }
            PanelButton {
                text: "Find an app"
                Accessible.name: "Find an application by name"
                onClicked: summary.openApplications()
            }
        }
        PlainLabel {
            visible: backend.paused || !!summary.snapshot.desktop_error
            Layout.fillWidth: true
            text: backend.paused ? "Monitoring paused · readings may be out of date" : "Application windows could not be read. Processes may still be available."
            color: summary.muted
            wrapMode: Text.WordWrap
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 72
            color: "transparent"
            border.color: summary.line
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32 * summary.textScale
                    color: summary.panel
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        PlainLabel { Layout.fillWidth: true; text: "APPLICATION"; color: summary.muted; font.bold: true }
                        PlainLabel { Layout.preferredWidth: 90 * summary.textScale; text: "CPU"; color: summary.muted; font.bold: true; horizontalAlignment: Text.AlignRight }
                        PlainLabel { Layout.preferredWidth: 104 * summary.textScale; text: "MEMORY"; color: summary.muted; font.bold: true; horizontalAlignment: Text.AlignRight }
                    }
                }
                ScrollView {
                    id: applicationScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: applicationScroll.availableWidth
                        spacing: 0
                        PlainLabel {
                            visible: summary.applications.length === 0
                            Layout.fillWidth: true
                            Layout.margins: 14
                            text: summary.snapshot.desktop_error ? "Application list unavailable." : Object.keys(summary.snapshot).length ? "No application windows found." : "Waiting for application data…"
                            color: summary.muted
                            wrapMode: Text.WordWrap
                        }
                        Repeater {
                            model: summary.applications
                            delegate: Button {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44 * summary.textScale
                                flat: true
                                text: modelData.name
                                Accessible.name: "Open " + modelData.name + " in Applications"
                                onClicked: summary.selectApplication(modelData.key)
                                background: Rectangle {
                                    color: parent.hovered || parent.activeFocus ? summary.panel : "transparent"
                                    border.color: parent.activeFocus ? summary.accent : summary.line
                                    border.width: parent.activeFocus ? 1 : 0
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: summary.line }
                                }
                                contentItem: RowLayout {
                                    spacing: 8
                                    Image {
                                        Layout.preferredWidth: 22 * summary.textScale
                                        Layout.preferredHeight: 22 * summary.textScale
                                        source: "image://icons/" + (modelData.icon || "application-x-executable")
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    PlainLabel { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; color: summary.fg }
                                    PlainLabel { Layout.preferredWidth: 90 * summary.textScale; text: summary.percent(modelData.cpu); color: summary.fg; horizontalAlignment: Text.AlignRight }
                                    PlainLabel { Layout.preferredWidth: 104 * summary.textScale; text: summary.bytes(modelData.memory); color: summary.fg; horizontalAlignment: Text.AlignRight }
                                }
                            }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            PlainLabel {
                Layout.fillWidth: true
                text: "Select an app to see its windows and close it safely."
                color: summary.muted
                elide: Text.ElideRight
            }
            PanelButton {
                objectName: "summaryViewAllButton"
                text: "View all"
                Accessible.name: "View all applications"
                onClicked: summary.openApplications()
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: width < 540 * summary.textScale ? 1 : 2
            columnSpacing: 8 * summary.textScale
            rowSpacing: 8 * summary.textScale
            Repeater {
                model: [
                    { label: "CPU", value: summary.percent(summary.system.cpu && summary.system.cpu.length ? summary.system.cpu[0].usage : null), field: "cpu" },
                    { label: "Memory", value: summary.memory.total ? summary.percent(100 * summary.memory.used / summary.memory.total) : "—", field: "memory" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: (summary.width < 540 * summary.textScale ? 64 : 92) * summary.textScale
                    color: summary.panel
                    border.color: summary.line
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8 * summary.textScale
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            PlainLabel { Layout.fillWidth: true; text: modelData.label; color: summary.muted; font.bold: true }
                            PlainLabel { text: modelData.value; color: summary.fg; font.bold: true; font.pixelSize: 17 * summary.textScale }
                        }
                        HistoryChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            points: summary.history
                            field: modelData.field
                            ink: summary.accent
                            grid: summary.line
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: "Open Performance for " + modelData.label
                        onClicked: summary.openPerformance()
                    }
                }
            }
        }
    }
}
