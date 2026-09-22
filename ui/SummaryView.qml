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
        return rows.slice(0, 5);
    }
    function percent(value) { return backend.percent(value); }
    function bytes(value) { return backend.bytes(value); }

    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 14 * summary.textScale
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 36
                PlainLabel {
                    Layout.fillWidth: true
                    text: backend.paused ? "Monitoring paused · readings may be out of date" : "Your computer at a glance"
                    color: backend.paused ? summary.accent : summary.muted
                    wrapMode: Text.WordWrap
                }
                PanelButton {
                    text: "Find an app"
                    Accessible.name: "Find an application by name"
                    onClicked: summary.openApplications()
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width < 540 * summary.textScale ? 1 : 2
                columnSpacing: 10 * summary.textScale
                rowSpacing: 10 * summary.textScale
                Repeater {
                    model: [
                        { label: "CPU", value: summary.percent(summary.system.cpu && summary.system.cpu.length ? summary.system.cpu[0].usage : null), detail: "Processor use", field: "cpu" },
                        { label: "Memory", value: summary.memory.total ? summary.percent(100 * summary.memory.used / summary.memory.total) : "—", detail: summary.memory.total ? summary.bytes(summary.memory.used) + " of " + summary.bytes(summary.memory.total) : "No reading yet", field: "memory" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: 138 * summary.textScale
                        color: summary.panel
                        border.color: summary.line
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12 * summary.textScale
                            spacing: 3
                            PlainLabel { text: modelData.label; color: summary.muted; font.bold: true }
                            RowLayout {
                                Layout.fillWidth: true
                                PlainLabel {
                                    text: modelData.value
                                    color: summary.fg
                                    font.bold: true
                                    font.pixelSize: 25 * summary.textScale
                                }
                                PlainLabel {
                                    Layout.fillWidth: true
                                    text: modelData.detail
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    color: summary.muted
                                }
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
            RowLayout {
                Layout.fillWidth: true
                PlainLabel {
                    Layout.fillWidth: true
                    text: "Running applications"
                    color: summary.fg
                    font.bold: true
                    font.pixelSize: 15 * summary.textScale
                }
                PanelButton {
                    text: "View all applications"
                    objectName: "summaryViewAllButton"
                    onClicked: summary.openApplications()
                }
            }
            PlainLabel {
                visible: !!summary.snapshot.desktop_error
                Layout.fillWidth: true
                text: "Application windows could not be read. Open Processes to see what is running."
                color: summary.muted
                wrapMode: Text.WordWrap
            }
            PlainLabel {
                visible: !summary.snapshot.desktop_error && summary.applications.length === 0
                Layout.fillWidth: true
                text: Object.keys(summary.snapshot).length ? "No application windows found." : "Waiting for application data…"
                color: summary.muted
            }
            Repeater {
                model: summary.applications
                delegate: Button {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * summary.textScale
                    flat: true
                    text: modelData.name
                    Accessible.name: "Open " + modelData.name + " in Applications"
                    onClicked: summary.selectApplication(modelData.key)
                    background: Rectangle {
                        color: parent.hovered || parent.activeFocus ? summary.panel : "transparent"
                        border.color: parent.activeFocus ? summary.accent : summary.line
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        Image {
                            Layout.preferredWidth: 24 * summary.textScale
                            Layout.preferredHeight: 24 * summary.textScale
                            source: "image://icons/" + (modelData.icon || "application-x-executable")
                            fillMode: Image.PreserveAspectFit
                        }
                        PlainLabel {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: summary.fg
                        }
                        PlainLabel {
                            text: summary.percent(modelData.cpu) + " CPU"
                            color: summary.muted
                        }
                        PlainLabel {
                            text: summary.bytes(modelData.memory)
                            color: summary.muted
                        }
                        PlainLabel { text: "›"; color: summary.accent }
                    }
                }
            }
            PlainLabel {
                Layout.fillWidth: true
                text: "Select an application to see its windows and close it safely."
                color: summary.muted
                wrapMode: Text.WordWrap
            }
        }
    }
}
