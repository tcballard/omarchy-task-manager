import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import TaskManager 1.0
import "Theme.js" as Theme

ApplicationWindow {
    id: root
    property real availableScreenWidth: Math.max(1, Screen.desktopAvailableWidth - 40)
    property real availableScreenHeight: Math.max(1, Screen.desktopAvailableHeight - 60)
    property int preferredPanelWidth: Math.min(availableScreenWidth, Math.max(640, backend.preference("width", 1120)))
    property int preferredPanelHeight: Math.min(availableScreenHeight, Math.max(420, backend.preference("height", 760)))
    width: preferredPanelWidth
    height: preferredPanelHeight
    minimumWidth: Math.min(640, availableScreenWidth)
    minimumHeight: Math.min(420, availableScreenHeight)
    visible: true
    title: "Task Manager"
    flags: Qt.Window | Qt.FramelessWindowHint
    property bool sidebarCollapsed: backend.preference("sidebarCollapsed", false)
    property bool compact: width < 900 * layoutScale
    property bool pinned: true
    property var columnWidths: Theme.savedWidths(backend.preference("columnWidths", "{}"))
    function columnWidth(column, total) {
        return Theme.columnWidth(columns, column, total, layoutScale, columnWidths);
    }
    function resizeColumn(key, pixels) {
        var widths = Object.assign({}, columnWidths);
        widths[key] = Math.max(key === "name" ? 120 : 48, Math.min(1200, pixels / layoutScale));
        columnWidths = widths;
    }
    function saveColumns() {
        backend.savePreference("columnWidths", JSON.stringify(columnWidths));
    }
    function resetColumns() {
        columnWidths = ({});
        saveColumns();
    }
    function toggleSidebar() {
        sidebarCollapsed = !sidebarCollapsed;
        backend.savePreference("sidebarCollapsed", sidebarCollapsed);
    }
    property bool seenActive: false
    property bool modalOpen: confirm.visible || runTask.visible || inspector.visible || tuning.visible
    property bool processPage: backend.page === "apps" || backend.page === "processes"
    property var pageNames: ({
            "summary": "Summary",
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
    property real baseSize: Theme.number(tokens, "font.base-size", 12, 8, 32)
    property real layoutScale: Math.max(1, fontSize("body", 12) / 12)
    function fontSize(name, fallback) {
        return Theme.number(tokens, "font." + name, fallback * baseSize / 12, 8, 48);
    }
    function showConfirmation(info) {
        if (modalOpen || !info.title)
            return;
        actionInfo = info;
        wasPaused = backend.paused;
        backend.paused = true;
        confirm.open();
    }
    function manage(request) {
        if (!modalOpen)
            showConfirmation(backend.prepareManagement(request));
    }
    onActiveChanged: {
        if (active)
            seenActive = true;
        else if (seenActive && !pinned && !root.modalOpen)
            root.close();
    }
    header: Rectangle {
        height: 44 * root.layoutScale + 12
        color: bg
        MouseArea {
            anchors.fill: parent
            onPressed: root.startSystemMove()
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 48
            spacing: 8
            ToolButton {
                objectName: "sidebarToggle"
                text: "☰"
                Accessible.name: root.sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: root.toggleSidebar()
            }
            PlainLabel {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: "TASK MANAGER"
                elide: Text.ElideRight
                font.pixelSize: root.fontSize("body", 12)
                font.bold: true
                font.letterSpacing: 1
                color: accent
            }
            PanelButton {
                visible: root.width >= 720 * root.layoutScale
                text: "Run new task"
                onClicked: runTask.open()
            }
            PanelButton {
                visible: !root.compact
                text: "Export"
                onClicked: backend.exportSnapshot()
            }
            PanelButton {
                visible: !root.compact
                text: "Stay open"
                checkable: true
                checked: root.pinned
                onClicked: root.pinned = !root.pinned
            }
            ToolButton {
                objectName: "windowMenuButton"
                text: "⋮"
                Accessible.name: "Task Manager options"
                onClicked: windowMenu.popup()
            }
        }
        ToolButton {
            objectName: "closePanelButton"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            text: "×"
            font.pixelSize: 22
            Accessible.name: "Close Task Manager"
            onClicked: root.close()
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
    MouseArea {
        objectName: "windowResizeGrip"
        z: 110
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 18
        height: 18
        cursorShape: Qt.SizeFDiagCursor
        onPressed: root.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        PlainLabel {
            anchors.centerIn: parent
            text: "◢"
            color: root.muted
            font.pixelSize: 12
        }
    }
    Shortcut {
        sequence: "Escape"
        enabled: !root.modalOpen
        onActivated: root.close()
    }
    Shortcut {
        sequence: "Ctrl+N"
        enabled: !root.modalOpen
        onActivated: runTask.open()
    }
    Shortcut {
        sequence: "F5"
        enabled: !root.modalOpen
        onActivated: backend.refresh()
    }
    Shortcut {
        sequence: "Delete"
        enabled: !root.modalOpen && root.processPage && !search.activeFocus && root.canAct
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
        var c = [
            {
                "label": "NAME",
                "key": "name",
                "width": -1
            },
            {
                "label": backend.page === "apps" ? "TASKS" : "PID",
                "key": backend.page === "apps" ? "count" : "pid",
                "width": 64
            },
            {
                "label": "CPU",
                "key": "cpu",
                "width": 72
            },
            {
                "label": "MEMORY",
                "key": "memory",
                "width": 102
            }
        ];
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
        return columnWidth(columns[0], total);
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
    function ask(force) {
        if (!modalOpen)
            showConfirmation(backend.prepareAction(force));
    }
    function rate(v) {
        return v === null || v === undefined ? "—" : backend.bytes(v) + "/s";
    }
    Shortcut {
        sequence: "Ctrl+F"
        enabled: !root.modalOpen
        onActivated: {
            if (backend.page === "summary" || backend.page === "performance")
                backend.page = "apps";
            search.forceActiveFocus();
        }
    }
    Shortcut {
        sequence: "Ctrl+0"
        enabled: !root.modalOpen
        onActivated: backend.page = "summary"
    }
    Shortcut {
        sequence: "Ctrl+1"
        enabled: !root.modalOpen
        onActivated: backend.page = "apps"
    }
    Shortcut {
        sequence: "Ctrl+2"
        enabled: !root.modalOpen
        onActivated: backend.page = "processes"
    }
    Shortcut {
        sequence: "Ctrl+3"
        enabled: !root.modalOpen
        onActivated: backend.page = "performance"
    }
    Item {
        id: workspaceScroll
        objectName: "workspaceScroll"
        anchors.fill: parent
        clip: true
        property real contentWidth: width
        property real contentHeight: height
        RowLayout {
            width: workspaceScroll.contentWidth
            height: workspaceScroll.contentHeight
            spacing: 0
            Rectangle {
                Layout.fillHeight: true
                objectName: "sidebar"
                Layout.preferredWidth: root.sidebarCollapsed ? 56 : 184 * root.layoutScale
                Layout.minimumWidth: Layout.preferredWidth
                Layout.maximumWidth: Layout.preferredWidth
                color: panel
                ScrollView {
                    id: navigationScroll
                    anchors.fill: parent
                    anchors.margins: root.sidebarCollapsed ? 4 : 12
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: navigationScroll.availableWidth
                        height: Math.max(navigationScroll.availableHeight, implicitHeight)
                        spacing: 7
                        PlainLabel {
                            visible: !root.sidebarCollapsed
                            text: "WORKSPACE"
                            font.pixelSize: root.fontSize("body-small", 11)
                            font.bold: true
                            font.letterSpacing: 1.3
                            color: muted
                            Layout.topMargin: 14
                            Layout.bottomMargin: 10
                        }
                        Repeater {
                            model: [
                                {
                                    "page": "summary",
                                    "name": "Summary",
                                    "mark": "⌂"
                                },
                                {
                                    "page": "apps",
                                    "name": "Applications",
                                    "mark": "▦"
                                },
                                {
                                    "page": "processes",
                                    "name": "Processes",
                                    "mark": "≡"
                                },
                                {
                                    "page": "performance",
                                    "name": "Performance",
                                    "mark": "↗"
                                },
                                {
                                    "page": "history",
                                    "name": "App history",
                                    "mark": "◷"
                                },
                                {
                                    "page": "startup",
                                    "name": "Startup apps",
                                    "mark": "↑"
                                },
                                {
                                    "page": "users",
                                    "name": "Users",
                                    "mark": "♙"
                                },
                                {
                                    "page": "services",
                                    "name": "Services",
                                    "mark": "⚙"
                                }
                            ]
                            delegate: Button {
                                Layout.minimumHeight: 34
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36 * root.layoutScale
                                text: root.sidebarCollapsed ? modelData.mark : modelData.mark + "   " + modelData.name
                                Accessible.name: modelData.name
                                ToolTip.visible: hovered && root.sidebarCollapsed
                                ToolTip.text: modelData.name
                                flat: true
                                checkable: true
                                checked: backend.page === modelData.page || (modelData.page === "services" && backend.page === "system-services")
                                contentItem: PlainLabel {
                                    text: parent.text
                                    color: parent.checked ? accent : fg
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: root.sidebarCollapsed ? 0 : 12
                                    horizontalAlignment: root.sidebarCollapsed ? Text.AlignHCenter : Text.AlignLeft
                                    elide: Text.ElideRight
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
                        PlainLabel {
                            visible: !root.sidebarCollapsed
                            text: "Refresh interval"
                            font.pixelSize: root.fontSize("body", 12)
                            color: muted
                        }
                        ComboBox {
                            visible: !root.sidebarCollapsed
                            Layout.preferredHeight: 36 * root.layoutScale
                            Layout.fillWidth: true
                            model: ["0.5 seconds", "1 second", "2 seconds", "5 seconds"]
                            currentIndex: [500, 1000, 2000, 5000].indexOf(backend.interval)
                            onActivated: backend.interval = [500, 1000, 2000, 5000][currentIndex]
                        }
                        PanelButton {
                            Layout.minimumHeight: 34
                            Layout.fillWidth: true
                            text: root.sidebarCollapsed ? (backend.paused ? "▶" : "Ⅱ") : (backend.paused ? "Resume live view" : "Pause live view")
                            implicitWidth: root.sidebarCollapsed ? 40 : 160
                            Accessible.name: backend.paused ? "Resume live view" : "Pause live view"
                            ToolTip.visible: hovered
                            ToolTip.text: Accessible.name
                            onClicked: backend.paused = !backend.paused
                        }
                        PlainLabel {
                            visible: !root.sidebarCollapsed
                            objectName: "versionLabel"
                            text: "v0.0.4 · Preview"
                            color: muted
                            font.pixelSize: root.fontSize("body-small", 11)
                            Layout.topMargin: 12
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: line
            }
            ColumnLayout {
                id: mainContent
                objectName: "mainContent"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.margins: root.compact ? 12 : 18
                spacing: root.height < 600 ? 8 : 14
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumHeight: 62
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 4
                        PlainLabel {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.pageNames[backend.page] || "Task Manager"
                            font.pixelSize: root.fontSize("heading", 16)
                            font.bold: true
                            color: fg
                        }
                        PlainLabel {
                            visible: !root.compact
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: backend.page === "summary" ? "Find what is busy and get back to work" : backend.page === "apps" ? "Running windows and their processes" : backend.page === "processes" ? "Processes, resource use, and controls" : backend.page === "performance" ? "Live resource use · 60-second history" : "Monitor and manage your system"
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
                        PlainLabel {
                            text: "CPU"
                            font.pixelSize: root.fontSize("body-small", 11)
                            color: muted
                        }
                        PlainLabel {
                            text: backend.percent(system.cpu && system.cpu.length ? system.cpu[0].usage : null)
                            font.pixelSize: root.fontSize("display", 24)
                            color: accent
                        }
                    }
                    Rectangle {
                        Layout.preferredHeight: 36 * root.layoutScale
                        Layout.preferredWidth: 1
                        color: line
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                    }
                    ColumnLayout {
                        Layout.minimumWidth: 90
                        Layout.preferredWidth: 90
                        spacing: 3
                        PlainLabel {
                            text: "MEMORY"
                            font.pixelSize: root.fontSize("body-small", 11)
                            color: muted
                        }
                        PlainLabel {
                            text: mem.total ? backend.percent(100 * mem.used / mem.total) : "—"
                            font.pixelSize: root.fontSize("display", 24)
                            color: fg
                        }
                    }
                }
                RowLayout {
                    visible: backend.page !== "performance" && backend.page !== "summary"
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
                        text: "Columns"
                        onClicked: columnsMenu.popup()
                    }
                    CheckBox {
                        visible: backend.page === "processes" && !root.compact
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
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    Layout.minimumHeight: 80
                    color: "transparent"
                    border.color: line
                    radius: 0
                    TableViewport {
                        objectName: "processTableViewport"
                        anchors.fill: parent
                        minimumContentWidth: Theme.tableWidth(root.columns, root.layoutScale, root.columnWidths) + 32
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            Row {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40 * root.layoutScale
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                spacing: 0
                                Repeater {
                                    model: root.columns
                                    delegate: ColumnHeader {
                                        required property var modelData
                                        objectName: "columnHeader_" + modelData.key
                                        width: root.columnWidth(modelData, parent.width)
                                        onResizeRequested: function (pixels) {
                                            root.resizeColumn(modelData.key, pixels);
                                        }
                                        onResizeFinished: root.saveColumns()
                                        onResetRequested: root.resetColumns()
                                        height: 40 * root.layoutScale
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
                                ScrollBar.vertical: ScrollBar {}
                                Keys.onUpPressed: backend.selectOffset(-1)
                                Keys.onDownPressed: backend.selectOffset(1)
                                Keys.onMenuPressed: contextMenu.popup()
                                delegate: Rectangle {
                                    id: row
                                    required property var entry
                                    required property int index
                                    width: list.width
                                    height: 38 * root.layoutScale
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
                                            PlainLabel {
                                                Layout.fillWidth: true
                                                text: entry.name
                                                color: fg
                                                elide: Text.ElideRight
                                                font.bold: backend.selected === entry.key
                                            }
                                            PlainLabel {
                                                visible: !!entry.protected
                                                text: "Protected"
                                                font.pixelSize: root.fontSize("caption", 10)
                                                color: muted
                                                Layout.rightMargin: 8
                                            }
                                        }
                                        Repeater {
                                            model: root.columns.slice(1)
                                            delegate: PlainLabel {
                                                required property var modelData
                                                width: root.columnWidth(modelData, parent.width)
                                                height: parent.height
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: Text.AlignRight
                                                text: root.cell(row.entry, modelData.key)
                                                color: fg
                                                font.pixelSize: root.fontSize("body", 12)
                                                rightPadding: 8
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: entry.name
                                    Accessible.selected: backend.selected === entry.key
                                }
                                PlainLabel {
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
                }
                SummaryView {
                    objectName: "summaryView"
                    visible: backend.page === "summary"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    snapshot: root.snap
                    history: backend.history
                    fg: root.fg
                    accent: root.accent
                    muted: root.muted
                    panel: root.panel
                    line: root.line
                    textScale: root.layoutScale
                    onOpenApplications: { backend.page = "apps"; search.forceActiveFocus(); }
                    onOpenPerformance: backend.page = "performance"
                    onSelectApplication: function(key) { backend.page = "apps"; backend.selected = key; }
                }
                ManagementView {
                    textScale: root.layoutScale
                    visible: !root.processPage && backend.page !== "performance" && backend.page !== "summary"
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
                        PlainLabel {
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
                                PlainLabel {
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
                                PlainLabel {
                                    text: (system.cores || 0) + " logical CPUs · " + (system.cpu_mhz ? (system.cpu_mhz / 1000).toFixed(2) + " GHz" : "60 seconds")
                                    color: muted
                                    font.pixelSize: root.fontSize("body", 12)
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                PlainLabel {
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
                                PlainLabel {
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
                                    PlainLabel {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 8
                                        text: modelData.name + "  " + backend.percent(modelData.usage)
                                        font.pixelSize: root.fontSize("body-small", 11)
                                        color: fg
                                    }
                                }
                            }
                        }
                        PlainLabel {
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
                        PlainLabel {
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
                                    PlainLabel {
                                        text: modelData.name + (modelData.state ? " · " + modelData.state : "")
                                        Layout.fillWidth: true
                                        color: fg
                                    }
                                    PlainLabel {
                                        text: "↓ " + root.rate(modelData.first_rate) + "     ↑ " + root.rate(modelData.second_rate)
                                        color: fg
                                        font.family: "monospace"
                                    }
                                    PlainLabel {
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
                        PlainLabel {
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
                                    PlainLabel {
                                        text: modelData.name
                                        Layout.fillWidth: true
                                        color: fg
                                    }
                                    PlainLabel {
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
                        PlainLabel {
                            visible: !(system.disks || []).length
                            text: "No readable block-device counters"
                            color: muted
                        }
                        PlainLabel {
                            text: "VOLUMES"
                            font.pixelSize: root.fontSize("body-small", 11)
                            font.bold: true
                            color: muted
                        }
                        PlainLabel {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: muted
                            text: system.mounts_status || ""
                        }
                        Repeater {
                            model: system.mounts || []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 5
                                RowLayout {
                                    Layout.fillWidth: true
                                    PlainLabel {
                                        text: modelData.name
                                        Layout.fillWidth: true
                                        color: fg
                                        elide: Text.ElideMiddle
                                    }
                                    PlainLabel {
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
                        PlainLabel {
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
                                    PlainLabel {
                                        text: modelData.name + " · " + modelData.driver
                                        Layout.fillWidth: true
                                        color: fg
                                    }
                                    PlainLabel {
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
                                PlainLabel {
                                    text: modelData.memory_total ? backend.bytes(modelData.memory_used || 0) + " / " + backend.bytes(modelData.memory_total) + " VRAM" : "VRAM counter unavailable"
                                    color: fg
                                }
                                PlainLabel {
                                    text: modelData.source
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    color: muted
                                    font.pixelSize: root.fontSize("body-small", 11)
                                }
                            }
                        }
                        PlainLabel {
                            visible: !(system.gpus || []).length
                            text: "No readable GPU devices in this session"
                            color: muted
                        }
                        PlainLabel {
                            text: "HARDWARE"
                            font.pixelSize: root.fontSize("body-small", 11)
                            font.bold: true
                            color: muted
                        }
                        PlainLabel {
                            text: system.hardware ? system.hardware.gpu_status : "GPU metrics unavailable"
                            color: muted
                        }
                        Repeater {
                            model: system.hardware ? system.hardware.batteries : []
                            delegate: PlainLabel {
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
                                delegate: PlainLabel {
                                    required property var modelData
                                    text: modelData.name + "  " + modelData.celsius.toFixed(1) + " °C"
                                    color: fg
                                }
                            }
                        }
                        PlainLabel {
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
                        visible: !!picked.key && root.height >= 600
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        clip: true
                        TextArea {
                            textFormat: TextEdit.PlainText
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
                    Flow {
                        objectName: "processActions"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: 6
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
                PlainLabel {
                    Layout.fillWidth: true
                    objectName: "statusLabel"
                    text: backend.status
                    color: backend.paused ? accent : muted
                    font.pixelSize: root.fontSize("body-small", 11)
                    wrapMode: Text.WordWrap
                    maximumLineCount: root.height < 600 ? 1 : 2
                    elide: Text.ElideRight
                }
            }
        }
    }
    Menu {
        id: windowMenu
        MenuItem {
            text: "Run new task"
            onTriggered: runTask.open()
        }
        MenuItem {
            text: "Export snapshot"
            onTriggered: backend.exportSnapshot()
        }
        MenuItem {
            objectName: "backgroundMonitoringToggle"
            text: "Background monitoring"
            checkable: true
            checked: backend.background.enabled
            enabled: !backend.background.busy
            onTriggered: backend.background.setEnabled(!backend.background.enabled)
        }
        MenuItem {
            text: backend.background.status
            enabled: false
            implicitWidth: 380 * root.layoutScale
            contentItem: PlainLabel {
                text: backend.background.status
                color: root.muted
                wrapMode: Text.WordWrap
            }
        }
        MenuItem {
            text: "Stay open"
            checkable: true
            checked: root.pinned
            onTriggered: root.pinned = checked
        }
        MenuSeparator {}
        MenuItem {
            text: "Collapse sidebar"
            checkable: true
            checked: root.sidebarCollapsed
            onTriggered: root.toggleSidebar()
        }
        MenuItem {
            text: backend.paused ? "Resume live view" : "Pause live view"
            onTriggered: backend.paused = !backend.paused
        }
        Menu {
            title: "Refresh interval"
            Repeater {
                model: [500, 1000, 2000, 5000]
                MenuItem {
                    required property var modelData
                    text: (modelData / 1000) + " seconds"
                    checkable: true
                    checked: backend.interval === modelData
                    onTriggered: backend.interval = modelData
                }
            }
        }
    }
    Menu {
        id: columnsMenu
        MenuItem {
            text: "Reset column widths"
            onTriggered: root.resetColumns()
        }
        MenuSeparator {
            visible: backend.page === "processes"
        }
        MenuItem {
            visible: backend.page === "processes"
            text: "Process tree"
            checkable: true
            checked: backend.tree
            onTriggered: backend.tree = checked
        }
        MenuItem {
            visible: backend.page === "processes"
            text: "Disk read/write"
            checkable: true
            checked: root.showIo
            onTriggered: root.showIo = checked
        }
        MenuItem {
            visible: backend.page === "processes"
            text: "GPU"
            checkable: true
            checked: root.showGpu
            onTriggered: root.showGpu = checked
        }
        MenuItem {
            visible: backend.page === "processes"
            text: "User"
            checkable: true
            checked: root.showOwner
            onTriggered: root.showOwner = checked
        }
        MenuItem {
            visible: backend.page === "processes"
            text: "Threads"
            checkable: true
            checked: root.showThreads
            onTriggered: root.showThreads = checked
        }
    }
    Shortcut {
        sequence: "Ctrl+4"
        enabled: !root.modalOpen
        onActivated: backend.page = "history"
    }
    Shortcut {
        sequence: "Ctrl+5"
        enabled: !root.modalOpen
        onActivated: backend.page = "startup"
    }
    Shortcut {
        sequence: "Ctrl+6"
        enabled: !root.modalOpen
        onActivated: backend.page = "users"
    }
    Shortcut {
        sequence: "Ctrl+7"
        enabled: !root.modalOpen
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
        MenuSeparator {}
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
        MenuSeparator {}
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
                if (!root.modalOpen)
                    root.showConfirmation(backend.prepareTree(false));
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
            PlainLabel {
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
            PlainLabel {
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
        onClosed: backend.dismissInspection()
        standardButtons: Dialog.Close
        ScrollView {
            anchors.fill: parent
            clip: true
            TextArea {
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: fg
                font.family: "monospace"
                font.pixelSize: root.fontSize("body", 12)
                text: backend.inspection.logs !== undefined ? (backend.inspection.logs || "No journal entries available.") : (backend.inspection.process ? "EXECUTABLE\n" + backend.inspection.executable + "\n\nWORKING DIRECTORY\n" + backend.inspection.cwd + "\n\nSTATUS\n" + backend.inspection.status + "\nCGROUP\n" + backend.inspection.cgroup + "\nOPEN FILES\n" + (backend.inspection.files || []).join("\n") + "\n\nTHREADS / WAIT CHANNELS\n" + (backend.inspection.threads || []).map(function (t) {
                        return t.tid + "  " + t.name + "  " + t.wait;
                    }).join("\n") + "\n\nMEMORY MAPS\n" + backend.inspection.maps + "\n" + backend.inspection.note : backend.inspection.message || "")
            }
        }
    }
    Connections {
        target: backend
        function onInspectionRequested() {
            inspector.open();
        }
    }
    Dialog {
        id: tuning
        objectName: "tuningDialog"
        anchors.centerIn: parent
        width: Math.min(560, root.width - 80)
        modal: true
        title: "Priority and CPU affinity"
        standardButtons: Dialog.Close
        ColumnLayout {
            width: parent.width
            spacing: 16
            PlainLabel {
                Layout.fillWidth: true
                text: "Applies to existing threads. Lower nice values mean higher priority; raising priority may be denied by Linux."
                wrapMode: Text.Wrap
                color: muted
            }
            RowLayout {
                PlainLabel {
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
            PlainLabel {
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
        header: PlainLabel {
            text: confirm.title
            padding: 12
            font.bold: true
            color: fg
            wrapMode: Text.Wrap
        }
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: PlainLabel {
            objectName: "confirmationBody"
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
