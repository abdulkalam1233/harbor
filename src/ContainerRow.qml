import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: row

    required property var modelData
    property bool selected: false
    property bool marked: false
    property var stats: null
    property bool busy: false
    property color stateColor
    property string stateText

    signal clicked(int modifiers)
    signal doubleClicked()
    signal markToggled()

    height: 64
    radius: Math.min(4, theme.radius)
    color: selected ? "#1c1c21" : hover.hovered ? "#151518" : "transparent"
    border.width: selected ? 1 : 0
    border.color: theme.accent

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        onClicked: mouse => row.clicked(mouse.modifiers)
        onDoubleClicked: row.doubleClicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 16
        spacing: 14

        CheckBox {
            checked: row.marked
            focusPolicy: Qt.NoFocus
            Accessible.name: row.modelData.name
            onClicked: {
                row.markToggled()
                checked = Qt.binding(() => row.marked)
            }
        }

        Rectangle {
            implicitWidth: 10
            implicitHeight: 10
            radius: 5
            color: row.stateColor
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: row.modelData.name
                font.bold: true
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: row.modelData.image
                opacity: 0.55
                elide: Text.ElideMiddle
            }
        }

        ColumnLayout {
            Layout.preferredWidth: 130
            spacing: 2
            visible: row.width > 560

            Label {
                Layout.fillWidth: true
                text: row.stats ? qsTr("CPU %1").arg(row.stats.cpu) : ""
                opacity: 0.55
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: row.stats ? qsTr("RAM %1").arg(row.stats.memory) : ""
                opacity: 0.55
                elide: Text.ElideRight
            }
        }

        Label {
            Layout.preferredWidth: 200
            text: row.modelData.ports
            opacity: 0.55
            elide: Text.ElideRight
            visible: row.width > 680
        }

        ColumnLayout {
            Layout.preferredWidth: 190
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: row.stateText
                color: row.stateColor
                horizontalAlignment: Text.AlignRight
            }
            Label {
                Layout.fillWidth: true
                text: row.modelData.status
                opacity: 0.5
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        BusyIndicator {
            implicitWidth: 28
            implicitHeight: 28
            running: row.busy
            opacity: running ? 1 : 0
        }
    }
}
