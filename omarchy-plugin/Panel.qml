import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "harbor.containers"
  ipcTarget: "harbor.containers"
  manageIpc: false

  readonly property var fixCommands: ({
    missing: "sudo pacman -S docker",
    denied: "sudo usermod -aG docker $USER",
    stopped: "sudo systemctl enable --now docker"
  })

  property var containers: []
  property string failure: ""
  property bool refreshing: false
  property bool refreshAgain: false

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

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    anchors.fill: parent
    bar: root.bar
    text: "󰡨"
    dimmed: root.failure !== ""
    labelText: root.failure === "" ? Commons.I18n.formatNumber(root.runningTotal) : ""
    tooltipText: root.tooltip
  }
}
