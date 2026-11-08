import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Popup {
    id: toast

    property string message

    function show(text) {
        message = text
        open()
        hideTimer.restart()
    }

    x: (parent.width - width) / 2
    y: parent.height - height - 72
    width: Math.min(560, parent.width - 40)
    padding: 14
    closePolicy: Popup.CloseOnPressOutside
    Material.roundedScale: theme.radius

    background: Rectangle {
        color: "#2a1215"
        border.color: "#7f1d1d"
        radius: Math.min(4, theme.radius)
    }

    contentItem: Label {
        text: toast.message
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: "#fca5a5"
    }

    Timer {
        id: hideTimer
        interval: 6000
        onTriggered: toast.close()
    }
}
