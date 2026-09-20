import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import TaskManager 1.0

ApplicationWindow {
    id: root
    width: Math.max(850, backend.preference("width", 1120))
    height: Math.max(560, backend.preference("height", 760))
    minimumWidth: 850
    minimumHeight: 560
    visible: true
    title: "Task Manager"
    flags: Qt.Window | Qt.FramelessWindowHint
    property bool pinned: true
    property bool seenActive: false
    property bool processPage: backend.page === "apps" || backend.page === "processes"
    property var pageNames: ({
            "apps": "Applications",
            "processes": "Processes",
            "performance": "Performance",
            "history": "App history",
            "startup": "Startup apps",
            "users": "Users",
            "services": "Services",
            "system-services": "Services"
        })
    property var tokens: snap.theme ? (snap.theme.shell || ({})) : ({})
    property real baseSize: Number(tokens["font.base-size"] || 12)
    function fontSize(name, fallback) {
        return Math.max(1, Number(tokens["font." + name] || fallback * baseSize / 12));
    }
    function manage(request) {
        actionInfo = backend.prepareManagement(request);
        if (actionInfo.title) {
            wasPaused = backend.paused;
            backend.paused = true;
            confirm.open();
        }
    }
    onActiveChanged: {
        if (active)
            seenActive = true;
        else if (seenActive && !pinned && !confirm.visible && !runTask.visible && !inspector.visible && !tuning.visible)
            root.close();
    }
    header: Rectangle {
        height: 44
        color: bg
        MouseArea {
            anchors.fill: parent
            onPressed: root.startSystemMove()
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 10
            spacing: 10
            Label {
                text: "TASK MANAGER"
                font.pixelSize: root.fontSize("body", 12)
                font.bold: true
                font.letterSpacing: 1
                color: accent
            }
            Label {
                text: "/ OMARCHY"
                font.pixelSize: root.fontSize("body-small", 11)
                color: muted
            }
            Item {
                Layout.fillWidth: true
            }
            PanelButton {
                text: "Run new task"
                onClicked: runTask.open()
            }
            PanelButton {
                text: "Export"
                onClicked: backend.exportSnapshot()
            }
            PanelButton {
                text: root.pinned ? "Stay open" : "Dismiss on blur"
                checkable: true
                checked: root.pinned
                onClicked: root.pinned = !root.pinned
                ToolTip.visible: hovered
                ToolTip.text: "Keep the panel open when another window receives focus"
            }
            ToolButton {
                text: "×"
                font.pixelSize: 22
                Accessible.name: "Close Task Manager"
                onClicked: root.close()
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: line
        }
    }
    Rectangle {
        z: 100
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: accent
    }
    Shortcut {
        sequence: "Escape"
        enabled: !confirm.visible && !runTask.visible && !inspector.visible && !tuning.visible
        onActivated: root.close()
    }
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: runTask.open()
    }
    Shortcut {
        sequence: "F5"
        onActivated: backend.refresh()
    }
    Shortcut {
        sequence: "Delete"
        enabled: root.processPage && !search.activeFocus && root.canAct
        onActivated: root.ask(false)
    }
    property var snap: backend.snapshot
    property var system: snap.system || ({})
    property var mem: system.memory || ({})
    property color bg: snap.theme && snap.theme.background ? snap.theme.background : "#15181e"
    property color fg: snap.theme && snap.theme.foreground ? snap.theme.foreground : "#e3e7ee"
    property color accent: snap.theme && snap.theme.accent ? snap.theme.accent : "#8cb4fa"
    property color panel: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, 0.045))
    property color line: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, 0.14))
    property color muted: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, 0.65))
    property var picked: backend.selection
    property bool canAct: picked.key !== undefined && !picked.protected && picked.uid === snap.uid && !backend.busy
    property bool perCoreGraphs: false
    property bool showIo: true
    property bool showGpu: true
    property bool showOwner: false
    property bool showThreads: false
    property var columns: {
        var c = [{
                "label": "NAME",
                "key": "name",
                "width": -1
            }, {
                "label": backend.page === "apps" ? "TASKS" : "PID",
                "key": backend.page === "apps" ? "count" : "pid",
                "width": 64
            }, {
                "label": "CPU",
                "key": "cpu",
                "width": 72
            }, {
                "label": "MEMORY",
                "key": "memory",
                "width": 102
            }];
        if (backend.page === "processes") {
            if (showIo)
                c.push({
                        "label": "DISK R/W",
                        "key": "io_rate",
                        "width": 108
                    });
            if (showGpu)
                c.push({
                        "label": "GPU",
                        "key": "gpu",
                        "width": 64
                    });
            if (showOwner)
                c.push({
                        "label": "USER",
                        "key": "user",
                        "width": 100
                    });
            if (showThreads)
                c.push({
                        "label": "THREADS",
                        "key": "threads",
                        "width": 70
                    });
        }
        return c;
    }
    function nameColumnWidth(total) {
        var reserved = 0;
        for (var i = 1; i < columns.length; i++)
            reserved += columns[i].width;
        return Math.max(120, total - reserved);
    }
    function cell(row, key) {
        var v = row[key];
        if (v === null || v === undefined)
            return "—";
        if (key === "cpu" || key === "gpu")
            return backend.percent(v);
        if (key === "memory")
            return backend.bytes(v);
        if (key === "io_rate")
            return rate(v);
        return String(v);
    }
    property var actionInfo: ({})
    property bool wasPaused: false
    color: bg
    palette.window: bg
    palette.windowText: fg
    palette.base: panel
    palette.text: fg
    palette.button: panel
    palette.buttonText: fg
    palette.highlight: accent
    palette.highlightedText: bg
    palette.mid: line
    palette.placeholderText: muted
    font.family: "monospace"
    font.pixelSize: root.fontSize("body", 12)
    onClosing: {
        backend.savePreference("width", width);
        backend.savePreference("height", height);
    }
    onVisibilityChanged: function (visibility) {
        backend.active(visibility !== Window.Minimized && visibility !== Window.Hidden);
    }
    function ask(force) {
        actionInfo = backend.prepareAction(force);
        if (actionInfo.title) {
            wasPaused = backend.paused;
            backend.paused = true;
            confirm.open();
        }
    }
    function rate(v) {
        return v === null || v === undefined ? "—" : backend.bytes(v) + "/s";
    }
    Shortcut {
        sequence: "Ctrl+F"
        onActivated: search.forceActiveFocus()
    }
    Shortcut {
        sequence: "Ctrl+1"
        onActivated: backend.page = "apps"
    }
    Shortcut {
        sequence: "Ctrl+2"
        onActivated: backend.page = "processes"
    }
    Shortcut {
        sequence: "Ctrl+3"
        onActivated: backend.page = "performance"
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 176
            color: panel
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 7
                Label {
                    text: "WORKSPACE"
                    font.pixelSize: root.fontSize("body-small", 11)
                    font.bold: true
                    font.letterSpacing: 1.3
                    color: muted
                    Layout.topMargin: 14
                    Layout.bottomMargin: 10
                }
                Repeater {
                    model: [{
                            "page": "apps",
                            "name": "Applications",
                            "mark": "▦"
                        }, {
                            "page": "processes",
                            "name": "Processes",
                            "mark": "≡"
                        }, {
                            "page": "performance",
                            "name": "Performance",
                            "mark": "↗"
                        }, {
                            "page": "history",
                            "name": "App history",
                            "mark": "◷"
                        }, {
                            "page": "startup",
                            "name": "Startup apps",
                            "mark": "↑"
                        }, {
                            "page": "users",
                            "name": "Users",
                            "mark": "♙"
                        }, {
                            "page": "services",
                            "name": "Services",
                            "mark": "⚙"
                        }]
                    delegate: Button {
                        Layout.minimumHeight: 34
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        text: modelData.mark + "   " + modelData.name
                        flat: true
                        checkable: true
                        checked: backend.page === modelData.page || (modelData.page === "services" && backend.page === "system-services")
                        contentItem: Label {
                            text: parent.text
                            color: parent.checked ? accent : fg
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 12
                            font.bold: parent.checked
                        }
                        background: Rectangle {
                            color: parent.checked ? Qt.tint(bg, Qt.rgba(accent.r, accent.g, accent.b, 0.12)) : "transparent"
                            radius: 0
                            border.color: parent.activeFocus ? accent : "transparent"
                        }
                        onClicked: backend.page = modelData.page
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
                Label {
                    text: "Refresh interval"
                    font.pixelSize: root.fontSize("body", 12)
                    color: muted
                }
                ComboBox {
                    Layout.preferredHeight: 36
                    Layout.fillWidth: true
                    model: ["0.5 seconds", "1 second", "2 seconds", "5 seconds"]
                    currentIndex: [500, 1000, 2000, 5000].indexOf(backend.interval)
                    onActivated: backend.interval = [500, 1000, 2000, 5000][currentIndex]
                }
                PanelButton {
                    Layout.minimumHeight: 34
                    Layout.fillWidth: true
                    text: backend.paused ? "Resume monitoring" : "Pause monitoring"
                    onClicked: backend.paused = !backend.paused
                }
                Label {
                    objectName: "versionLabel"
                    text: "v0.1.0 · Preview"
                    color: muted
                    font.pixelSize: root.fontSize("body-small", 11)
                    Layout.topMargin: 12
                }
            }
        }
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: line
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 62
                ColumnLayout {
                    spacing: 4
                    Label {
                        text: root.pageNames[backend.page] || "Task Manager"
                        font.pixelSize: root.fontSize("heading", 16)
                        font.bold: true
                        color: fg
                    }
                    Label {
                        text: backend.page === "apps" ? "Running windows and their processes" : backend.page === "processes" ? "Processes, resource use, and controls" : backend.page === "performance" ? "Live resource use · 60-second history" : "Monitor and manage your system"
                        font.pixelSize: root.fontSize("body", 12)
                        color: muted
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    Layout.minimumWidth: 90
                    Layout.preferredWidth: 90
                    spacing: 3
                    Label {
                        text: "CPU"
                        font.pixelSize: root.fontSize("body-small", 11)
                        color: muted
                    }
                    Label {
                        text: backend.percent(system.cpu && system.cpu.length ? system.cpu[0].usage : null)
                        font.pixelSize: root.fontSize("display", 24)
                        color: accent
                    }
                }
                Rectangle {
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: 1
                    color: line
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                }
                ColumnLayout {
                    Layout.minimumWidth: 90
                    Layout.preferredWidth: 90
                    spacing: 3
                    Label {
                        text: "MEMORY"
                        font.pixelSize: root.fontSize("body-small", 11)
                        color: muted
                    }
                    Label {
                        text: mem.total ? backend.percent(100 * mem.used / mem.total) : "—"
                        font.pixelSize: root.fontSize("display", 24)
                        color: fg
                    }
                }
            }
            RowLayout {
                visible: backend.page !== "performance"
                Layout.fillWidth: true
                spacing: 12
                TextField {
                    id: search
                    objectName: "searchField"
                    Layout.preferredHeight: 38
                    Layout.fillWidth: true
                    placeholderText: "Search by name" + (backend.page === "processes" ? ", user or PID" : "") + "    Ctrl+F"
                    text: backend.query
                    onTextEdited: backend.query = text
                    selectByMouse: true
                    Accessible.name: "Search processes and applications"
                }
                PanelButton {
                    visible: backend.page === "processes"
                    text: "Columns"
                    onClicked: columnsMenu.popup()
                }
                CheckBox {
                    visible: backend.page === "processes"
                    text: "Process tree"
                    checked: backend.tree
                    onToggled: backend.tree = checked
                }
                ToolButton {
                    Layout.minimumHeight: 34
                    text: backend.descending ? "↓" : "↑"
                    Accessible.name: "Reverse sort order"
                    onClicked: backend.descending = !backend.descending
                }
            }
            Rectangle {
                visible: root.processPage
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.color: line
                radius: 0
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    Row {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        spacing: 0
                        Repeater {
                            model: root.columns
                            delegate: ToolButton {
                                Layout.minimumHeight: 34
                                required property var modelData
                                width: modelData.width === -1 ? root.nameColumnWidth(parent.width) : modelData.width
                                height: 40
                                text: modelData.label + (backend.sort === modelData.key ? (backend.descending ? " ↓" : " ↑") : "")
                                font.pixelSize: root.fontSize("body-small", 11)
                                font.bold: true
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
                        id: list
                        objectName: "processList"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.processPage ? backend.rows : null
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                        }
                        Keys.onUpPressed: backend.selectOffset(-1)
                        Keys.onDownPressed: backend.selectOffset(1)
                        Keys.onMenuPressed: contextMenu.popup()
                        delegate: Rectangle {
                            id: row
                            required property var entry
                            required property int index
                            width: list.width
                            height: 38
                            color: backend.selected === entry.key ? Qt.tint(bg, Qt.rgba(accent.r, accent.g, accent.b, 0.15)) : (hover.hovered ? panel : "transparent")
                            Rectangle {
                                width: 3
                                height: parent.height
                                color: accent
                                visible: backend.selected === entry.key
                            }
                            HoverHandler {
                                id: hover
                            }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onTapped: function (point, button) {
                                    backend.selected = row.entry.key;
                                    list.forceActiveFocus();
                                    if (button === Qt.RightButton)
                                        contextMenu.popup();
                                }
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 0
                                RowLayout {
                                    width: root.nameColumnWidth(parent.width)
                                    height: parent.height
                                    spacing: 10
                                    Item {
                                        visible: (row.entry.depth || 0) > 0
                                        Layout.preferredWidth: (row.entry.depth || 0) * 12
                                        Layout.fillHeight: true
                                    }
                                    Image {
                                        visible: backend.page === "apps"
                                        source: backend.page === "apps" ? "image://icons/" + (entry.icon || "application-x-executable") : ""
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        sourceSize.width: 32
                                        sourceSize.height: 32
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: entry.name
                                        color: fg
                                        elide: Text.ElideRight
                                        font.bold: backend.selected === entry.key
                                    }
                                    Label {
                                        visible: !!entry.protected
                                        text: "Protected"
                                        font.pixelSize: root.fontSize("caption", 10)
                                        color: muted
                                        Layout.rightMargin: 8
                                    }
                                }
                                Repeater {
                                    model: root.columns.slice(1)
                                    delegate: Label {
                                        required property var modelData
                                        width: modelData.width
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: root.cell(row.entry, modelData.key)
                                        color: fg
                                        font.pixelSize: 12
                                        rightPadding: 8
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            Accessible.role: Accessible.ListItem
                            Accessible.name: entry.name
                            Accessible.selected: backend.selected === entry.key
                        }
                        Label {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            width: parent.width - 40
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            color: muted
                            text: backend.query ? "No matching results" : backend.page === "apps" ? (snap.desktop_error ? "Application discovery needs a Hyprland session.\nProcesses and Performance are available." : "No application windows found.") : "Waiting for process data…"
                        }
                    }
                }
            }
            ManagementView {
                visible: !root.processPage && backend.page !== "performance"
                Layout.fillWidth: true
                Layout.fillHeight: true
                bg: root.bg
                fg: root.fg
                accent: root.accent
                line: root.line
                muted: root.muted
                onRequest: function (request) {
                    root.manage(request);
                }
                onInspectLogs: backend.loadLogs()
            }
            ScrollView {
                id: perf
                Layout.minimumHeight: 0
                Layout.preferredHeight: 1
                visible: backend.page === "performance"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: perf.availableWidth
                    spacing: 20
                    Label {
                        text: (system.cpu_model || "CPU") + " · " + (system.process_count || 0) + " processes / " + (system.thread_count || 0) + " threads"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: muted
                        font.pixelSize: root.fontSize("body", 12)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 24
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "CPU HISTORY"
                                font.pixelSize: root.fontSize("body-small", 11)
                                font.bold: true
                                color: muted
                            }
                            HistoryChart {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 135
                                points: backend.history
                                field: "cpu"
                                ink: accent
                                grid: line
                            }
                            Label {
                                text: (system.cores || 0) + " logical CPUs · " + (system.cpu_mhz ? (system.cpu_mhz / 1000).toFixed(2) + " GHz" : "60 seconds")
                                color: muted
                                font.pixelSize: root.fontSize("body", 12)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "MEMORY HISTORY"
                                font.pixelSize: root.fontSize("body-small", 11)
                                font.bold: true
                                color: muted
                            }
                            HistoryChart {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 135
                                points: backend.history
                                field: "memory"
                                ink: fg
                                grid: line
                            }
                            Label {
                                text: backend.bytes(mem.used || 0) + " / " + backend.bytes(mem.total || 0)
                                color: muted
                                font.pixelSize: root.fontSize("body", 12)
                            }
                        }
                    }
                    CheckBox {
                        text: "Show per-core history"
                        checked: root.perCoreGraphs
                        onToggled: root.perCoreGraphs = checked
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: system.cpu ? system.cpu.slice(1) : []
                            delegate: Rectangle {
                                required property var modelData
                                width: 96
                                height: root.perCoreGraphs ? 70 : 30
                                color: panel
                                HistoryChart {
                                    anchors.fill: parent
                                    anchors.topMargin: 28
                                    visible: root.perCoreGraphs
                                    points: backend.history
                                    field: modelData.name
                                    ink: accent
                                    grid: line
                                }
                                radius: 3
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8
                                    text: modelData.name + "  " + backend.percent(modelData.usage)
                                    font.pixelSize: root.fontSize("body-small", 11)
                                    color: fg
                                }
                            }
                        }
                    }
                    Label {
                        text: "Available: " + backend.bytes(mem.available || 0) + "    Cache: " + backend.bytes(mem.cache || 0) + "    Swap: " + backend.bytes(mem.swap_used || 0) + " / " + backend.bytes(mem.swap_total || 0)
                        color: muted
                        font.pixelSize: root.fontSize("body", 12)
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: line
                    }
                    Label {
                        text: "NETWORK"
                        font.pixelSize: root.fontSize("body-small", 11)
                        font.bold: true
                        color: muted
                    }
                    Repeater {
                        model: system.network || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: modelData.name + (modelData.state ? " · " + modelData.state : "")
                                    Layout.fillWidth: true
                                    color: fg
                                }
                                Label {
                                    text: "↓ " + root.rate(modelData.first_rate) + "     ↑ " + root.rate(modelData.second_rate)
                                    color: fg
                                    font.family: "monospace"
                                }
                                Label {
                                    text: backend.bytes(modelData.first) + " received"
                                    color: muted
                                    Layout.preferredWidth: 150
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            HistoryChart {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                points: backend.history
                                autoScale: true
                                field: "network:" + modelData.name + ":first"
                                field2: "network:" + modelData.name + ":second"
                                ink: accent
                                secondInk: muted
                                grid: line
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: line
                    }
                    Label {
                        text: "DISK ACTIVITY"
                        font.pixelSize: root.fontSize("body-small", 11)
                        font.bold: true
                        color: muted
                    }
                    Repeater {
                        model: system.disks || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: modelData.name
                                    Layout.fillWidth: true
                                    color: fg
                                }
                                Label {
                                    text: "Read " + root.rate(modelData.first_rate) + "     Write " + root.rate(modelData.second_rate) + " · " + backend.percent(modelData.active_percent) + " active"
                                    color: fg
                                    font.family: "monospace"
                                }
                            }
                            HistoryChart {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                points: backend.history
                                autoScale: true
                                field: "disks:" + modelData.name + ":first"
                                field2: "disks:" + modelData.name + ":second"
                                ink: accent
                                secondInk: muted
                                grid: line
                            }
                        }
                    }
                    Label {
                        visible: !(system.disks || []).length
                        text: "No readable block-device counters"
                        color: muted
                    }
                    Label {
                        text: "VOLUMES"
                        font.pixelSize: root.fontSize("body-small", 11)
                        font.bold: true
                        color: muted
                    }
                    Repeater {
                        model: system.mounts || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 5
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: modelData.name
                                    Layout.fillWidth: true
                                    color: fg
                                    elide: Text.ElideMiddle
                                }
                                Label {
                                    text: backend.bytes(modelData.available) + " available / " + backend.bytes(modelData.total)
                                    color: muted
                                    font.pixelSize: root.fontSize("body", 12)
                                }
                            }
                            ProgressBar {
                                Layout.fillWidth: true
                                value: modelData.total ? modelData.used / modelData.total : 0
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: line
                    }
                    Label {
                        text: "GPU"
                        color: muted
                        font.pixelSize: root.fontSize("body-small", 11)
                        font.bold: true
                    }
                    Repeater {
                        model: system.gpus || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: modelData.name + " · " + modelData.driver
                                    Layout.fillWidth: true
                                    color: fg
                                }
                                Label {
                                    text: backend.percent(modelData.usage)
                                    color: accent
                                }
                            }
                            HistoryChart {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 70
                                points: backend.history
                                field: "gpu:" + modelData.device
                                ink: accent
                                grid: line
                            }
                            Label {
                                text: modelData.memory_total ? backend.bytes(modelData.memory_used || 0) + " / " + backend.bytes(modelData.memory_total) + " VRAM" : "VRAM counter unavailable"
                                color: fg
                            }
                            Label {
                                text: modelData.source
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: muted
                                font.pixelSize: root.fontSize("body-small", 11)
                            }
                        }
                    }
                    Label {
                        visible: !(system.gpus || []).length
                        text: "No readable GPU devices in this session"
                        color: muted
                    }
                    Label {
                        text: "HARDWARE"
                        font.pixelSize: root.fontSize("body-small", 11)
                        font.bold: true
                        color: muted
                    }
                    Label {
                        text: system.hardware ? system.hardware.gpu_status : "GPU metrics unavailable"
                        color: muted
                    }
                    Repeater {
                        model: system.hardware ? system.hardware.batteries : []
                        delegate: Label {
                            required property var modelData
                            text: modelData.name + "   " + modelData.percent + "%   " + modelData.status
                            color: fg
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 16
                        Repeater {
                            model: system.hardware ? system.hardware.sensors : []
                            delegate: Label {
                                required property var modelData
                                text: modelData.name + "  " + modelData.celsius.toFixed(1) + " °C"
                                color: fg
                            }
                        }
                    }
                    Label {
                        text: "Load averages: " + (system.load || "—") + "    Uptime: " + (system.uptime ? Math.floor(system.uptime / 3600) + "h " + Math.floor(system.uptime % 3600 / 60) + "m" : "—")
                        color: muted
                        font.pixelSize: root.fontSize("body", 12)
                    }
                }
            }
            ColumnLayout {
                visible: root.processPage
                Layout.fillWidth: true
                spacing: 12
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    clip: true
                    TextArea {
                        text: {
                            var key = backend.selected;
                            var snap = backend.snapshot;
                            return backend.details();
                        }
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: muted
                        font.pixelSize: root.fontSize("body", 12)
                        background: null
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: picked.key ? (picked.protected ? "Desktop/session process protected" : "Selected: " + picked.name) : "Select a row to manage it"
                        color: muted
                        font.pixelSize: root.fontSize("body", 12)
                        elide: Text.ElideRight
                    }
                    PanelButton {
                        Layout.minimumHeight: 34
                        visible: backend.page === "apps"
                        text: "Show window"
                        enabled: root.canAct
                        onClicked: backend.windowAction(false)
                    }
                    PanelButton {
                        Layout.minimumHeight: 34
                        text: backend.page === "apps" ? "Close window" : "Terminate"
                        enabled: root.canAct
                        onClicked: backend.page === "apps" ? backend.windowAction(true) : root.ask(false)
                    }
                    PanelButton {
                        visible: backend.page === "processes"
                        text: "Details"
                        enabled: !!picked.key && !backend.busy
                        onClicked: backend.inspect()
                    }
                    PanelButton {
                        visible: root.processPage
                        text: "More ▾"
                        enabled: !!picked.key
                        onClicked: contextMenu.popup()
                    }
                    PanelButton {
                        Layout.minimumHeight: 34
                        objectName: "forceQuitButton"
                        text: "Force quit…"
                        enabled: root.canAct
                        onClicked: root.ask(true)
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                objectName: "statusLabel"
                text: backend.status
                color: backend.paused ? accent : muted
                font.pixelSize: root.fontSize("body-small", 11)
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }
    Menu {
        id: columnsMenu
        MenuItem {
            text: "Disk read/write"
            checkable: true
            checked: root.showIo
            onTriggered: root.showIo = checked
        }
        MenuItem {
            text: "GPU"
            checkable: true
            checked: root.showGpu
            onTriggered: root.showGpu = checked
        }
        MenuItem {
            text: "User"
            checkable: true
            checked: root.showOwner
            onTriggered: root.showOwner = checked
        }
        MenuItem {
            text: "Threads"
            checkable: true
            checked: root.showThreads
            onTriggered: root.showThreads = checked
        }
    }
    Shortcut {
        sequence: "Ctrl+4"
        onActivated: backend.page = "history"
    }
    Shortcut {
        sequence: "Ctrl+5"
        onActivated: backend.page = "startup"
    }
    Shortcut {
        sequence: "Ctrl+6"
        onActivated: backend.page = "users"
    }
    Shortcut {
        sequence: "Ctrl+7"
        onActivated: backend.page = "services"
    }
    Menu {
        id: contextMenu
        MenuItem {
            text: "Restart application…"
            visible: backend.page === "apps"
            enabled: root.canAct && !!picked.desktop_file
            onTriggered: root.manage({
                    "category": "restart",
                    "verb": "Restart application"
                })
        }
        MenuItem {
            text: "Create core dump…"
            visible: backend.page === "processes"
            enabled: root.canAct
            onTriggered: root.manage({
                    "category": "process",
                    "verb": "dump"
                })
        }
        MenuItem {
            text: "Details"
            visible: backend.page === "processes"
            enabled: !!picked.key && !backend.busy
            onTriggered: backend.inspect()
        }
        MenuItem {
            text: "Open file location"
            visible: backend.page === "processes"
            enabled: !!picked.key
            onTriggered: backend.openExecutable()
        }
        MenuItem {
            text: "Copy details"
            enabled: !!picked.key
            onTriggered: backend.copyDetails()
        }
        MenuSeparator {
        }
        MenuItem {
            text: "Priority / CPU affinity…"
            visible: backend.page === "processes"
            enabled: root.canAct
            onTriggered: tuning.open()
        }
        MenuItem {
            text: "Lower priority (nice 10)…"
            visible: backend.page === "processes"
            enabled: root.canAct
            onTriggered: root.manage({
                    "category": "process",
                    "verb": "nice",
                    "nice": Math.max(10, picked.nice || 0)
                })
        }
        MenuItem {
            text: picked.state === "T" ? "Resume…" : "Suspend…"
            visible: backend.page === "processes"
            enabled: root.canAct
            onTriggered: root.manage({
                    "category": "process",
                    "verb": picked.state === "T" ? "resume" : "suspend"
                })
        }
        MenuSeparator {
        }
        MenuItem {
            text: "Show window"
            visible: backend.page === "apps"
            enabled: root.canAct
            onTriggered: backend.windowAction(false)
        }
        MenuItem {
            text: backend.page === "apps" ? "Close window" : "Terminate…"
            enabled: root.canAct
            onTriggered: backend.page === "apps" ? backend.windowAction(true) : root.ask(false)
        }
        MenuItem {
            text: "End process tree…"
            visible: backend.page === "processes"
            enabled: root.canAct
            onTriggered: {
                root.actionInfo = backend.prepareTree(false);
                if (root.actionInfo.title) {
                    root.wasPaused = backend.paused;
                    backend.paused = true;
                    confirm.open();
                }
            }
        }
        MenuItem {
            text: "Force quit…"
            enabled: root.canAct
            onTriggered: root.ask(true)
        }
    }
    Dialog {
        id: runTask
        anchors.centerIn: parent
        width: Math.min(600, root.width - 80)
        modal: true
        title: "Run new task"
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: command.forceActiveFocus()
        onAccepted: backend.launch(command.text)
        ColumnLayout {
            width: parent.width
            spacing: 14
            Label {
                Layout.fillWidth: true
                text: "Enter an executable and arguments. Use double quotes for paths containing spaces."
                wrapMode: Text.Wrap
                color: muted
            }
            TextField {
                id: command
                objectName: "newTaskCommand"
                Layout.fillWidth: true
                placeholderText: "firefox --new-window"
                selectByMouse: true
                onAccepted: {
                    backend.launch(text);
                    runTask.close();
                }
            }
            Label {
                text: "Runs as your user. Shell operators are not evaluated."
                color: muted
                font.pixelSize: root.fontSize("body-small", 11)
            }
        }
    }
    Dialog {
        id: inspector
        objectName: "inspectionDialog"
        anchors.centerIn: parent
        width: Math.min(860, root.width - 80)
        height: Math.min(600, root.height - 100)
        modal: true
        title: "Process details / Service journal"
        standardButtons: Dialog.Close
        ScrollView {
            anchors.fill: parent
            clip: true
            TextArea {
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: fg
                font.family: "monospace"
                font.pixelSize: root.fontSize("body", 12)
                text: backend.inspection.logs || (backend.inspection.process ? "EXECUTABLE\n" + backend.inspection.executable + "\n\nWORKING DIRECTORY\n" + backend.inspection.cwd + "\n\nSTATUS\n" + backend.inspection.status + "\nCGROUP\n" + backend.inspection.cgroup + "\nOPEN FILES\n" + (backend.inspection.files || []).join("\n") + "\n\nTHREADS / WAIT CHANNELS\n" + (backend.inspection.threads || []).map(function (t) {
                            return t.tid + "  " + t.name + "  " + t.wait;
                        }).join("\n") + "\n\nMEMORY MAPS\n" + backend.inspection.maps + "\n" + backend.inspection.note : backend.inspection.message || "")
            }
        }
    }
    Connections {
        target: backend
        function onInspectionChanged() {
            inspector.open();
        }
    }
    Dialog {
        id: tuning
        anchors.centerIn: parent
        width: Math.min(560, root.width - 80)
        modal: true
        title: "Priority and CPU affinity"
        standardButtons: Dialog.Close
        ColumnLayout {
            width: parent.width
            spacing: 16
            Label {
                Layout.fillWidth: true
                text: "Applies to existing threads. Lower nice values mean higher priority; raising priority may be denied by Linux."
                wrapMode: Text.Wrap
                color: muted
            }
            RowLayout {
                Label {
                    text: "Nice value"
                    color: fg
                }
                SpinBox {
                    id: niceValue
                    from: -20
                    to: 19
                    value: root.picked.nice || 0
                    editable: true
                }
                PanelButton {
                    text: "Apply…"
                    onClicked: {
                        tuning.close();
                        root.manage({
                                "category": "process",
                                "verb": "nice",
                                "nice": niceValue.value
                            });
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                text: "CPU affinity · comma-separated CPU numbers. Invalid or unavailable CPUs are rejected by the kernel."
                wrapMode: Text.Wrap
                color: muted
            }
            RowLayout {
                TextField {
                    id: affinity
                    Layout.fillWidth: true
                    placeholderText: "0,1,2,3"
                }
                PanelButton {
                    text: "Apply…"
                    enabled: /^\d+(,\d+)*$/.test(affinity.text)
                    onClicked: {
                        var cpus = affinity.text.split(",").map(Number);
                        tuning.close();
                        root.manage({
                                "category": "process",
                                "verb": "affinity",
                                "cpus": cpus
                            });
                    }
                }
            }
        }
    }
    Dialog {
        id: confirm
        objectName: "confirmationDialog"
        anchors.centerIn: parent
        width: Math.min(560, root.width - 80)
        modal: true
        title: root.actionInfo.title || "Confirm action"
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Label {
            text: root.actionInfo.body || ""
            wrapMode: Text.Wrap
            color: fg
        }
        onAccepted: {
            backend.confirmAction();
            backend.paused = root.wasPaused;
        }
        onRejected: {
            backend.cancelAction();
            backend.paused = root.wasPaused;
        }
    }
}
