import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: configPage

    property alias cfg_refreshInterval: refreshIntervalSpin.value
    property alias cfg_autoScaleGraphs: autoScaleSwitch.checked
    property alias cfg_manualMaxGraphValue: maxGraphValueSpin.value
    property alias cfg_showBackground: showBackgroundSwitch.checked
    property alias cfg_backgroundOpacity: backgroundOpacitySlider.value

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20

        SpinBox {
            id: refreshIntervalSpin
            Kirigami.FormData.label: "Refresh Interval (seconds):"
            from: 1
            to: 300
            stepSize: 1
            value: 10
        }

        CheckBox {
            id: autoScaleSwitch
            Kirigami.FormData.label: "Graph Scaling:"
            text: "Auto-scale graphs based on traffic"
            checked: true
        }

        SpinBox {
            id: maxGraphValueSpin
            visible: !autoScaleSwitch.checked
            Kirigami.FormData.label: "Max Graph Value (kB/s):"
            from: 10
            to: 100000
            stepSize: 10
            value: 100
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Appearance"
        }

        CheckBox {
            id: showBackgroundSwitch
            Kirigami.FormData.label: "Background:"
            text: "Show background"
            checked: true
        }

        RowLayout {
            visible: showBackgroundSwitch.checked
            Kirigami.FormData.label: "Background Opacity:"
            spacing: 10

            Slider {
                id: backgroundOpacitySlider
                Layout.fillWidth: true
                from: 0.0
                to: 1.0
                stepSize: 0.05
                value: 0.85
            }

            Label {
                text: Math.round(backgroundOpacitySlider.value * 100) + "%"
                Layout.minimumWidth: 40
            }
        }

        Label {
            Kirigami.FormData.label: " "
            text: "Note: Configure Fritz!Box credentials in ~/.config/fritzplasmoid.ini"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.italic: true
        }
    }
}
