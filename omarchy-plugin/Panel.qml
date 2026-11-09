import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "harbor.containers"
  ipcTarget: "harbor.containers"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var fixCommands: ({
    missing: "sudo pacman -S docker",
    denied: "sudo usermod -aG docker $USER",
    stopped: "sudo systemctl enable --now docker"
  })

  property var containers: []
  property string failure: ""
  property bool refreshing: false
  property bool refreshAgain: false
  property var busyIds: []
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property string harborCommand: "omarchy-launch-or-focus harbor"
  readonly property int listedCount: failure === "" ? containers.length : 0
  readonly property int stopCount: listedCount + 1
  readonly property int harborStop: listedCount
  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

  onOpenedChanged: {
    if (!opened)
      return
    cursorIndex = 0
    cursorActive = true
  }

  readonly property int runningTotal: Model.runningCount(containers)
  readonly property string tooltip: failure !== "" ? failureText() : healthyText()

  function refresh() {
    if (refreshing) {
      refreshAgain = true
      return
    }
    refreshing = true
    listProcess.command = Model.listCommand()
    listProcess.running = true
  }

  function handleListExit(exitCode, stdout, stderr) {
    if (exitCode === 0)
      acceptListing(stdout)
    else
      failure = Model.failureKind(stderr + stdout, spawnFailed(exitCode, stdout, stderr))
    refreshing = false
    if (refreshAgain) {
      refreshAgain = false
      refresh()
    }
  }

  function spawnFailed(exitCode, stdout, stderr) {
    return exitCode < 0 && stdout === "" && stderr === ""
  }

  function acceptListing(stdout) {
    var next = Model.parseContainers(stdout)
    if (!Model.sameContainers(containers, next))
      containers = next
    failure = ""
  }

  function isBusy(id) {
    return busyIds.indexOf(id) >= 0
  }

  function perform(action, id) {
    var command = Model.actionCommand(action, id)
    if (isBusy(id) || command === null)
      return
    busyIds = busyIds.concat([id])
    actionProcess.createObject(root, { containerId: id, command: command, running: true })
  }

  function finishAction(id, exitCode, stdout, stderr) {
    busyIds = busyIds.filter(function (busyId) { return busyId !== id })
    if (exitCode !== 0)
      failure = Model.failureKind(stderr + stdout, spawnFailed(exitCode, stdout, stderr))
    refresh()
  }

  function toggleContainer(container) {
    perform(Model.toggleAction(container), container.id)
  }

  function openHarbor() {
    close()
    if (bar)
      bar.run(harborCommand)
  }

  function moveCursor(step) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(stopCount - 1, cursorIndex + step))
    scrollCursorIntoView()
  }

  function setCursor(index) {
    cursorActive = true
    cursorIndex = index
  }

  function activateCursor() {
    if (cursorIndex === harborStop)
      openHarbor()
    else
      toggleContainer(containers[cursorIndex])
  }

  function scrollCursorIntoView() {
    var item = panelFlick ? panelFlick.cursorItem(cursorIndex) : null
    if (item)
      panelFlick.reveal(item)
  }

  function healthyText() {
    if (containers.length === 0)
      return strings.t("tooltip.none")
    return strings.tn("tooltip.running", containers.length)
      .arg(Commons.I18n.formatNumber(runningTotal))
      .arg(Commons.I18n.formatNumber(containers.length))
  }

  function failureText() {
    return strings.t("failure." + failure).arg(fixCommands[failure] || "")
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Process {
    id: listProcess
    stdout: StdioCollector { id: listStdout; waitForEnd: true }
    stderr: StdioCollector { id: listStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.handleListExit(exitCode, String(listStdout.text || ""), String(listStderr.text || ""))
    }
  }

  Component {
    id: actionProcess
    Process {
      property string containerId: ""
      stdout: StdioCollector { id: actionStdout; waitForEnd: true }
      stderr: StdioCollector { id: actionStderr; waitForEnd: true }
      onExited: function(exitCode) {
        root.finishAction(containerId, exitCode, String(actionStdout.text || ""), String(actionStderr.text || ""))
        destroy()
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰡨"
    dimmed: root.failure !== ""
    tooltipText: root.tooltip
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(480))

    content: PanelKeyCatcher {
      property alias panelFlick: flick
      implicitHeight: column.implicitHeight + footerGap + harborButton.implicitHeight
      anchors.fill: parent
      readonly property real footerGap: Style.space(8)
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onTabRequested: function(direction) { root.moveCursor(direction) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: harborButton.top
        anchors.bottomMargin: parent.footerGap
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: scrolls
        readonly property bool scrolls: contentHeight > height
        ScrollBar.vertical: ScrollBar { id: scrollBar; policy: ScrollBar.AsNeeded }

        function cursorItem(index) {
          return index < root.listedCount ? rows.itemAt(index) : null
        }

        function reveal(item) {
          var top = item.mapToItem(contentItem, 0, 0).y
          var bottom = top + item.height
          if (top < contentY)
            contentY = top
          else if (bottom > contentY + height)
            contentY = bottom - height
        }

        Column {
          id: column
          width: flick.width - (flick.scrolls ? scrollBar.width + Style.space(4) : 0)
          spacing: Style.space(8)

          PanelSectionHeader {
            width: parent.width
            text: strings.t("panel.title")
          }

          Text {
            width: parent.width
            visible: root.failure === ""
            text: root.healthyText()
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Qt.darker(Commons.Color.foreground, 1.4)
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.failure !== ""
            text: root.failure !== "" ? root.failureText() : ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Commons.Color.foreground
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            visible: root.failure === "" && root.containers.length === 0
            text: strings.t("panel.empty")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Commons.Color.foreground
            font.pixelSize: Style.font.body
          }

          Repeater {
            id: rows
            model: root.listedCount

            ContainerRow {
              required property int index
              width: column.width
              container: root.containers[index]
              hasCursor: root.cursorActive && root.cursorIndex === index
              onCursorRequested: root.setCursor(index)
            }
          }
        }
      }

      Button {
        id: harborButton
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: strings.t("action.openHarbor")
        bordered: true
        hasCursor: root.cursorActive && root.cursorIndex === root.harborStop
        onHovered: function(isHovered) { if (isHovered) root.setCursor(root.harborStop) }
        onClicked: root.openHarbor()
      }
    }
  }

  component ContainerRow: RowLayout {
    id: row

    property var container
    property bool hasCursor: false
    readonly property bool busy: root.isBusy(container.id)

    signal cursorRequested()

    spacing: Style.space(8)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        text: row.container.name
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Commons.Color.foreground
        font.pixelSize: Style.font.body
      }

      Text {
        Layout.fillWidth: true
        text: row.container.image
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Qt.darker(Commons.Color.foreground, 1.4)
        font.pixelSize: Style.font.caption
      }

      Text {
        Layout.fillWidth: true
        text: strings.t("state." + row.container.state)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Commons.Color.foreground
        font.pixelSize: Style.font.caption
      }
    }

    Button {
      text: row.busy ? strings.t("action.busy") : strings.t("action." + Model.toggleAction(row.container))
      enabled: !row.busy
      bordered: true
      hasCursor: row.hasCursor
      onHovered: function(isHovered) { if (isHovered) row.cursorRequested() }
      onClicked: root.toggleContainer(row.container)
    }
  }
}
