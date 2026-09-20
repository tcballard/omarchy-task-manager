import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme

Item {
    id: view
    property real textScale: 1
    property color bg
    property color fg
    property color accent
    property color line
    property color muted
    property var picked: backend.selection
    property string pageError: backend.page === "history" ? ((backend.snapshot.usage || {}).error || "") : backend.snapshot.management_page === backend.page ? ((backend.snapshot.management || {}).error || "") : ""
    property bool services: backend.page === "services" || backend.page === "system-services"
    property var columns: backend.page === "history" ? [{
            "key": "name",
            "label": "APPLICATION",
            "width": -1
        }, {
            "key": "cpu_seconds",
            "label": "CPU TIME",
            "width": 104
        }, {
            "key": "read",
            "label": "READ",
            "width": 110
        }, {
            "key": "write",
            "label": "WRITE",
            "width": 110
        }, {
            "key": "peak_memory",
            "label": "PEAK RSS",
            "width": 110
        }] : backend.page === "users" ? [{
            "key": "name",
            "label": "USER",
            "width": -1
        }, {
            "key": "count",
            "label": "PROCESSES",
            "width": 94
        }, {
            "key": "cpu",
            "label": "CPU",
            "width": 90
        }, {
            "key": "memory",
            "label": "MEMORY",
            "width": 120
        }] : services ? [{
            "key": "name",
            "label": "SERVICE",
            "width": -1
        }, {
            "key": "state",
            "label": "STATE",
            "width": 114
        }, {
            "key": "sub",
            "label": "STATUS",
            "width": 114
        }] : [{
            "key": "name",
            "label": "APPLICATION",
            "width": -1
        }, {
            "key": "state",
            "label": "STARTUP",
            "width": 146
        }, {
            "key": "impact",
            "label": "IMPACT",
            "width": 130
        }]
    function columnWidth(column, total) {
        return Theme.columnWidth(columns, column, total, textScale);
    }
    signal request(var request)
    signal inspectLogs
    function cell(entry, key) {
        var v = entry[key];
        if (v === undefined || v === null)
            return "—";
        if (["read", "write", "peak_memory", "memory"].indexOf(key) >= 0)
            return backend.bytes(v);
        if (key === "cpu")
            return backend.percent(v);
        if (key === "cpu_seconds")
            return Number(v).toFixed(1) + " s";
        return String(v);
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        RowLayout {
            visible: view.services
            PlainLabel {
                text: "Scope"
                color: muted
            }
            ComboBox {
                model: ["Your services", "System services"]
                currentIndex: backend.page === "system-services" ? 1 : 0
                onActivated: backend.page = currentIndex === 1 ? "system-services" : "services"
            }
            Item {
                Layout.fillWidth: true
            }
            PlainLabel {
                text: "systemd"
                color: muted
            }
        }
        PlainLabel {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: muted
            font.pixelSize: 12 * view.textScale
            text: backend.page === "history" ? (backend.snapshot.usage ? backend.snapshot.usage.note : "") : backend.page === "users" ? "Resource use by account. Select your account to lock or sign out a session." : backend.page === "startup" ? "Manage apps at login. Hyprland launch scripts appear as configuration entries." : "Start, stop, restart, and inspect services. Permissions are enforced by systemd."
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            border.color: line
            TableViewport {
                objectName: "managementTableViewport"
                anchors.fill: parent
                minimumContentWidth: Theme.tableWidth(view.columns, view.textScale) + 24
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    Row {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36 * view.textScale
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        spacing: 0
                        Repeater {
                            model: view.columns
                            delegate: ToolButton {
                                required property var modelData
                                width: view.columnWidth(modelData, parent.width)
                                height: 36 * view.textScale
                                text: modelData.label + (backend.sort === modelData.key ? (backend.descending ? " ↓" : " ↑") : "")
                                font.pixelSize: 11 * view.textScale
                                onClicked: {
                                    if (backend.sort === modelData.key)
                                        backend.descending = !backend.descending;
                                    else
                                        backend.sort = modelData.key;
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: line
                    }
                    ListView {
                        id: rows
                        objectName: "managementList"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: view.visible ? backend.rows : null
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                        }
                        Keys.onUpPressed: backend.selectOffset(-1)
                        Keys.onDownPressed: backend.selectOffset(1)
                        delegate: Rectangle {
                            id: row
                            required property var entry
                            required property int index
                            width: rows.width
                            height: 40 * view.textScale
                            color: backend.selected === entry.key ? Qt.rgba(accent.r, accent.g, accent.b, 0.15) : hot.hovered ? Qt.rgba(fg.r, fg.g, fg.b, 0.04) : "transparent"
                            HoverHandler {
                                id: hot
                            }
                            TapHandler {
                                onTapped: {
                                    backend.selected = row.entry.key;
                                    rows.forceActiveFocus();
                                }
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 0
                                Repeater {
                                    model: view.columns
                                    delegate: PlainLabel {
                                        required property var modelData
                                        width: view.columnWidth(modelData, parent.width)
                                        height: 40 * view.textScale
                                        verticalAlignment: Text.AlignVCenter
                                        text: view.cell(row.entry, modelData.key)
                                        color: fg
                                        elide: Text.ElideRight
                                        horizontalAlignment: modelData.width === -1 ? Text.AlignLeft : Text.AlignHCenter
                                        font.pixelSize: 12 * view.textScale
                                        ToolTip.visible: hovered.hovered
                                        ToolTip.text: text
                                        HoverHandler {
                                            id: hovered
                                        }
                                    }
                                }
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: entry.name
                            Accessible.selected: backend.selected === entry.key
                        }
                        PlainLabel {
                            anchors.centerIn: parent
                            width: parent.width - 48
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: muted
                            visible: rows.count === 0
                            text: backend.query ? "No matching results" : view.pageError ? view.pageError : backend.page === "history" ? "Usage history will appear as processes are sampled." : "No entries found."
                        }
                    }
                }
            }
        }
        PlainLabel {
            Layout.fillWidth: true
            visible: !!view.pageError && rows.count > 0
            text: view.pageError
            wrapMode: Text.Wrap
            color: muted
            font.pixelSize: 11 * view.textScale
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            clip: true
            TextArea {
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: muted
                font.pixelSize: 12 * view.textScale
                background: null
                text: picked.key ? (picked.command || picked.description || picked.key) + (picked.enabled ? " · At login/boot: " + picked.enabled : "") + (picked.path ? "\n" + picked.path : "") : "Select a row to inspect or manage it."
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            PanelButton {
                visible: backend.page === "startup"
                text: picked.state === "Disabled" ? "Enable at login…" : "Disable at login…"
                enabled: !!picked.editable && !backend.busy
                onClicked: view.request({
                        "category": "startup",
                        "enabled": picked.state === "Disabled"
                    })
            }
            PanelButton {
                visible: backend.page === "startup" && picked.kind === "hyprland"
                text: "Open configuration"
                onClicked: Qt.openUrlExternally("file://" + picked.path)
            }
            Repeater {
                model: view.services ? ["start", "stop", "restart", "enable", "disable"] : []
                delegate: PanelButton {
                    required property string modelData
                    text: modelData.charAt(0).toUpperCase() + modelData.slice(1) + "…"
                    enabled: !!picked.key && !backend.busy
                    onClicked: view.request({
                            "category": "service",
                            "verb": modelData
                        })
                }
            }
            PanelButton {
                visible: view.services
                text: "View logs"
                enabled: !!picked.key && !backend.busy
                onClicked: view.inspectLogs()
            }
            PanelButton {
                visible: backend.page === "history"
                text: "Reset usage history…"
                enabled: !backend.busy
                onClicked: view.request({
                        "category": "history",
                        "verb": "reset"
                    })
            }
            PanelButton {
                visible: backend.page === "users"
                text: "Show processes"
                enabled: !!picked.key
                onClicked: backend.filterUser(picked.uid)
            }
            ComboBox {
                id: session
                visible: backend.page === "users"
                model: picked.sessions || []
                textRole: "session"
                displayText: count ? "Session " + currentText : "No sessions"
                implicitWidth: 140
            }
            PanelButton {
                visible: backend.page === "users"
                text: "Lock"
                enabled: picked.uid === backend.snapshot.uid && session.count > 0 && !backend.busy
                onClicked: view.request({
                        "category": "session",
                        "verb": "lock",
                        "session": session.currentText
                    })
            }
            PanelButton {
                visible: backend.page === "users"
                text: "Sign out…"
                enabled: picked.uid === backend.snapshot.uid && session.count > 0 && !backend.busy
                onClicked: view.request({
                        "category": "session",
                        "verb": "logout",
                        "session": session.currentText
                    })
            }
        }
    }
}
