import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: overlay

    property var entries: []
    signal dismissed()

    color: "#cc000000"

    MouseArea {
        anchors.fill: parent
        onClicked: overlay.dismissed()
    }

    Rectangle {
        anchors.centerIn: parent
        width: grid.implicitWidth + 56
        height: grid.implicitHeight + 56
        color: "#18181b"
        radius: theme.radius

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: 2
            rowSpacing: 10
            columnSpacing: 28

            Repeater {
                model: overlay.entries

                Label {
                    required property string modelData
                    required property int index
                    text: modelData
                    font.bold: index % 2 === 0
                    color: index % 2 === 0 ? theme.accent : palette.text
                }
            }
        }
    }
}
