import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1100
    height: 700
    minimumWidth: 720
    minimumHeight: 460
    visible: true
    title: "Harbor"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property bool helpVisible: false
    property string selectedId: ""
    readonly property int selectedIndex: backend.containers.findIndex(c => c.id === selectedId)
    readonly property var selected: selectedIndex >= 0 ? backend.containers[selectedIndex] : null
    readonly property int runningCount: backend.containers.filter(c => c.state === "running").length
    readonly property bool modalOpen: confirmRemove.visible || helpVisible
    property var markedIds: []
    readonly property var marked: backend.containers.filter(c => markedIds.includes(c.id))
    readonly property bool bulkMode: marked.length > 0

    function isRunning(container) { return container !== null && container.state === "running" }
    function isStopped(container) { return !isRunning(container) }

    function toggleRunning() {
        if (bulkMode) marked.every(isRunning) ? stopMarked() : startMarked()
        else if (selected) backend.perform(isRunning(selected) ? "stop" : "start", selected.id)
    }

    function startMarked() { backend.performEach("start", marked.filter(isStopped).map(c => c.id)) }
    function stopMarked() { backend.performEach("stop", marked.filter(isRunning).map(c => c.id)) }

    function toggleMark(id) {
        markedIds = markedIds.includes(id) ? markedIds.filter(m => m !== id) : markedIds.concat(id)
    }

    function markRangeTo(id) {
        const to = backend.containers.findIndex(c => c.id === id)
        const from = selectedIndex < 0 ? to : selectedIndex
        const range = backend.containers.slice(Math.min(from, to), Math.max(from, to) + 1).map(c => c.id)
        markedIds = markedIds.concat(range.filter(r => !markedIds.includes(r)))
    }

    function markAll() { markedIds = backend.containers.map(c => c.id) }
    function clearMarks() { markedIds = [] }

    function clickRow(id, modifiers) {
        if (modifiers & Qt.ControlModifier) toggleMark(id)
        else if (modifiers & Qt.ShiftModifier) markRangeTo(id)
        selectedId = id
    }

    function dismiss() {
        if (helpVisible) helpVisible = false
        else if (bulkMode) clearMarks()
        else backend.closeLogs()
    }
    function act(action) { if (selected) backend.perform(action, selected.id) }
    function askRemove() {
        if (bulkMode) confirmRemove.ask(marked)
        else if (selected) confirmRemove.ask([selected])
    }

    function toggleLogs() {
        if (!selected) return
        if (backend.logsId === selected.id) backend.closeLogs()
        else backend.openLogs(selected.id, selected.name)
    }

    function move(step) {
        const count = backend.containers.length
        if (count === 0) return
        const index = selectedIndex < 0 ? 0 : Math.max(0, Math.min(count - 1, selectedIndex + step))
        selectedId = backend.containers[index].id
        list.positionViewAtIndex(index, ListView.Contain)
    }

    function stateColor(state) {
        return ({ running: "#4ade80", paused: "#facc15", restarting: "#facc15", dead: "#f87171" })[state] || "#71717a"
    }

    function stateLabel(state) {
        translator.language
        return ({
            running: qsTr("Running"),
            exited: qsTr("Stopped"),
            paused: qsTr("Paused"),
            restarting: qsTr("Restarting"),
            created: qsTr("Created"),
            removing: qsTr("Removing"),
            dead: qsTr("Dead")
        })[state] || state
    }

    function shortcutList() {
        translator.language
        return [
            "↑ ↓  J K", qsTr("Select a container"),
            "Space", qsTr("Start or stop"),
            "M", qsTr("Select or unselect"),
            "Ctrl+A", qsTr("Select all"),
            "R", qsTr("Restart"),
            "L", qsTr("Show or hide logs"),
            "X", qsTr("Remove"),
            "F5", qsTr("Refresh now"),
            "Esc", qsTr("Clear selection, close logs or help"),
            "?", qsTr("Show or hide shortcuts"),
            "Q", qsTr("Quit")
        ]
    }

    component PrimaryButton: Button {
        id: primaryButton
        focusPolicy: Qt.NoFocus
        Material.foreground: enabled ? theme.accentForeground : "#71717a"
        background: Rectangle {
            implicitWidth: 88
            implicitHeight: 40
            radius: theme.radius
            color: primaryButton.enabled ? theme.accent : "#26262a"
            opacity: primaryButton.down ? 0.8 : 1
        }
    }

    Connections {
        target: backend
        function onContainersChanged() {
            if (win.selectedIndex < 0 && backend.containers.length > 0)
                win.selectedId = backend.containers[0].id
        }
        function onActionFailed(message) { toast.show(message) }
    }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; enabled: !confirmRemove.visible; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: Qt.quit() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.toggleRunning() }
    Shortcut { sequence: "M"; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: if (win.selected) win.toggleMark(win.selectedId) }
    Shortcut { sequence: StandardKey.SelectAll; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.markAll() }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.act("restart") }
    Shortcut { sequence: "L"; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.toggleLogs() }
    Shortcut { sequences: ["X", StandardKey.Delete]; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.askRemove() }
    Shortcut { sequences: ["Up", "K"]; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.move(-1) }
    Shortcut { sequences: ["Down", "J"]; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: win.move(1) }
    Shortcut { sequences: ["F5", StandardKey.Refresh]; context: Qt.ApplicationShortcut; enabled: !win.modalOpen; onActivated: backend.refresh() }
    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: !confirmRemove.visible
        onActivated: win.dismiss()
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Label { text: "Harbor"; font.pixelSize: 22; font.bold: true }
                Label {
                    text: qsTr("%n containers", "", backend.containers.length) + "  ·  " + qsTr("%n running", "", win.runningCount)
                    opacity: 0.6
                    visible: backend.loaded
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: qsTr("Harbor uses CPU %1% · RAM %2")
                        .arg(selfUsage.cpuPercent.toFixed(1))
                        .arg(Qt.locale().formattedDataSize(selfUsage.memoryBytes, 1))
                    opacity: 0.45
                }
                Label { text: qsTr("Press ? for shortcuts"); opacity: 0.45 }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: backend.error !== ""
                implicitHeight: errorLabel.implicitHeight + 24
                radius: Math.min(4, theme.radius)
                color: "#2a1215"
                border.color: "#7f1d1d"

                Label {
                    id: errorLabel
                    anchors.fill: parent
                    anchors.margins: 12
                    text: backend.error
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: "#fca5a5"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: list
                        anchors.fill: parent
                        model: backend.containers
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        delegate: ContainerRow {
                            width: ListView.view.width
                            selected: modelData.id === win.selectedId
                            marked: win.markedIds.includes(modelData.id)
                            stats: backend.stats[modelData.id] || null
                            busy: backend.busyIds.includes(modelData.id)
                            stateColor: win.stateColor(modelData.state)
                            stateText: win.stateLabel(modelData.state)
                            onClicked: modifiers => win.clickRow(modelData.id, modifiers)
                            onMarkToggled: win.toggleMark(modelData.id)
                            onDoubleClicked: { win.selectedId = modelData.id; win.toggleLogs() }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: backend.loaded && backend.containers.length === 0 && backend.error === ""
                        text: qsTr("No containers yet. Run one with docker run and it shows up here.")
                        opacity: 0.5
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: !backend.loaded && backend.error === ""
                    }
                }

                LogsPane {
                    visible: backend.logsId !== ""
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width * 0.5
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: win.bulkMode

                PrimaryButton {
                    text: qsTr("Start")
                    enabled: win.marked.some(win.isStopped)
                    onClicked: win.startMarked()
                }
                PrimaryButton {
                    text: qsTr("Stop")
                    enabled: win.marked.some(win.isRunning)
                    onClicked: win.stopMarked()
                }
                Button { text: qsTr("Remove"); flat: true; focusPolicy: Qt.NoFocus; onClicked: win.askRemove() }
                Button {
                    text: qsTr("Select all")
                    flat: true
                    focusPolicy: Qt.NoFocus
                    enabled: win.marked.length < backend.containers.length
                    onClicked: win.markAll()
                }
                Button { text: qsTr("Clear selection"); flat: true; focusPolicy: Qt.NoFocus; onClicked: win.clearMarks() }
                Item { Layout.fillWidth: true }
                Label { text: qsTr("%n selected", "", win.marked.length); opacity: 0.6 }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: !win.bulkMode
                enabled: win.selected !== null

                PrimaryButton {
                    text: win.isRunning(win.selected) ? qsTr("Stop") : qsTr("Start")
                    onClicked: win.toggleRunning()
                }
                Button { text: qsTr("Restart"); flat: true; focusPolicy: Qt.NoFocus; onClicked: win.act("restart") }
                Button {
                    text: backend.logsId !== "" && backend.logsId === win.selectedId ? qsTr("Hide logs") : qsTr("Logs")
                    flat: true
                    focusPolicy: Qt.NoFocus
                    onClicked: win.toggleLogs()
                }
                Button { text: qsTr("Remove"); flat: true; focusPolicy: Qt.NoFocus; onClicked: win.askRemove() }
                Button {
                    text: qsTr("Select all")
                    flat: true
                    focusPolicy: Qt.NoFocus
                    enabled: win.marked.length < backend.containers.length
                    onClicked: win.markAll()
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: win.selected ? win.selected.name : ""
                    opacity: 0.6
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 320
                }
            }
        }

        RemoveDialog { id: confirmRemove }

        Toast { id: toast }

        HelpOverlay {
            anchors.fill: parent
            visible: win.helpVisible
            entries: win.shortcutList()
            onDismissed: win.helpVisible = false
        }
    }
}
