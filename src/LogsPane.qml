import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    color: "#141417"
    radius: theme.radius

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: qsTr("Logs: %1").arg(backend.logsName)
                font.bold: true
                elide: Text.ElideRight
            }
            ToolButton {
                text: qsTr("Close")
                focusPolicy: Qt.NoFocus
                Material.roundedScale: theme.radius
                onClicked: backend.closeLogs()
            }
        }

        ScrollView {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            TextArea {
                id: logText
                text: backend.logs
                readOnly: true
                selectByMouse: true
                focusPolicy: Qt.NoFocus
                wrapMode: TextEdit.NoWrap
                textFormat: TextEdit.PlainText
                font.family: "monospace"
                font.pixelSize: 12
                background: null

                // The log is a tail, so new output belongs in view.
                onTextChanged: cursorPosition = length
            }
        }

        Label {
            visible: backend.logs === ""
            text: qsTr("No log output")
            opacity: 0.5
        }
    }
}
