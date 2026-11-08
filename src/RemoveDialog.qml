import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Dialog {
    id: dialog

    property var targets: []

    function ask(containers) {
        targets = containers
        open()
    }

    anchors.centerIn: parent
    modal: true
    width: Math.min(460, parent.width - 40)
    title: targets.length === 1 ? qsTr("Remove %1?").arg(targets[0].name) : qsTr("Remove %n containers?", "", targets.length)
    Material.roundedScale: theme.radius

    background: Rectangle {
        color: "#1c1c21"
        radius: theme.radius
    }

    Overlay.modal: Rectangle { color: "#99000000" }

    header: Label {
        text: dialog.title
        font.pixelSize: 20
        elide: Text.ElideRight
        padding: 24
        bottomPadding: 0
    }

    onAccepted: backend.performEach("remove", targets.map(c => c.id))

    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.ApplicationShortcut
        enabled: dialog.visible
        onActivated: dialog.accept()
    }

    Label {
        width: parent.width
        text: targets.length === 1 ? qsTr("If it's running it is killed first. Its image and volumes are kept.")
                                   : qsTr("Running ones are killed first. Their images and volumes are kept.")
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    footer: DialogButtonBox {
        background: null
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: qsTr("Remove")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
}
