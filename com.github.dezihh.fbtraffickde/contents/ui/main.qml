// KDE 6 Plasma Plasmoid for Fritz!Box Traffic Monitor
// Based on stock-monitor-widget pattern for KDE 6 compatibility
// Uses Plasma5Support for executing external scripts (compatibility layer)

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // --- CONFIGURATION ---
    Plasmoid.backgroundHints: Plasmoid.configuration.showBackground ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    // Configuration properties with defaults
    property int refreshInterval: Plasmoid.configuration.refreshInterval || 10
    property bool autoScaleGraphs: Plasmoid.configuration.autoScaleGraphs !== false
    property real manualMaxGraphValue: Plasmoid.configuration.manualMaxGraphValue || 100.0
    property bool showBackground: Plasmoid.configuration.showBackground !== false
    property real backgroundOpacity: Plasmoid.configuration.backgroundOpacity || 0.85

    // --- Graph data properties ---
    property var upHistory: []
    property var downHistory: []
    property int maxPoints: 50
    property real maxValueForGraph: manualMaxGraphValue

    // --- Display properties ---
    property string uploadValue: "Loading..."
    property string downloadValue: "Loading..."
    property bool hasError: false

    // --- Style properties ---
    property int borderWidth: 1
    property int topBottomMarginForContent: 3
    property int labelSpacing: 2
    property int graphSpacing: 3
    property int gridCells: 10
    property int cornerRadius: 6

    // --- Colors ---
    property color uploadColor: "#4bb648"
    property color downloadColor: "#2fa1e8"
    property color loadingColor: "gray"
    property color bgColor: Qt.rgba(0.1, 0.1, 0.15, root.backgroundOpacity)

    // DataSource for executing the Python script
    Plasma5Support.DataSource {
        id: trafficSource
        engine: "executable"
        interval: root.refreshInterval * 1000  // Convert seconds to milliseconds
        
        // Connect to the script on component load
        Component.onCompleted: {
            // Get the path to the Python script
            var basePath = Qt.resolvedUrl(".");
            basePath = basePath.toString().replace("/ui/", "/code/");
            basePath = basePath.replace("file://", "");
            var scriptPath = basePath + "Traffic.py";
            connectSource("python3 " + scriptPath);
        }
        
        onNewData: function(source, data) {
            processTrafficData(data);
        }
    }

    // Process the data from the script execution
    function processTrafficData(data) {
        // Check if stdout data exists
        if (!data || !data["stdout"]) {
            root.hasError = true;
            root.uploadValue = "Error";
            root.downloadValue = "Error";
            return;
        }

        var stdout = data["stdout"].toString().trim();
        if (stdout === "") {
            root.hasError = true;
            root.uploadValue = "Error";
            root.downloadValue = "Error";
            return;
        }

        try {
            var obj = JSON.parse(stdout);

            // Check for error in response
            if (obj.error) {
                root.hasError = true;
                root.uploadValue = obj.upload || "Error";
                root.downloadValue = obj.download || "Error";
                // Still push 0 values to history to keep graphs updating
                pushHistoryValue(0, 0);
                return;
            }

            root.hasError = false;

            // Update display values
            root.uploadValue = obj.upload + " kB/s";
            root.downloadValue = obj.download + " kB/s";

            // Parse numeric values
            var uploadVal = parseFloat(String(obj.upload).replace(",", "."));
            var downloadVal = parseFloat(String(obj.download).replace(",", "."));

            pushHistoryValue(isNaN(uploadVal) ? 0 : uploadVal, isNaN(downloadVal) ? 0 : downloadVal);

        } catch (e) {
            console.log("FB-Traffic-KDE: JSON parse error: " + e);
            root.hasError = true;
            root.uploadValue = "ParseErr";
            root.downloadValue = "ParseErr";
            pushHistoryValue(0, 0);
        }
    }

    // Helper function to push values to history and update scaling
    function pushHistoryValue(uploadVal, downloadVal) {
        // Update upload history
        var newUpHistory = root.upHistory.slice();
        newUpHistory.push(uploadVal);
        if (newUpHistory.length > root.maxPoints) {
            newUpHistory.shift();
        }
        root.upHistory = newUpHistory;

        // Update download history
        var newDownHistory = root.downHistory.slice();
        newDownHistory.push(downloadVal);
        if (newDownHistory.length > root.maxPoints) {
            newDownHistory.shift();
        }
        root.downHistory = newDownHistory;

        // Auto-scale graphs if enabled - use the same scale for both
        if (root.autoScaleGraphs) {
            var maxVal = root.manualMaxGraphValue;
            for (var i = 0; i < root.upHistory.length; i++) {
                if (root.upHistory[i] > maxVal) maxVal = root.upHistory[i];
            }
            for (var j = 0; j < root.downHistory.length; j++) {
                if (root.downHistory[j] > maxVal) maxVal = root.downHistory[j];
            }
            root.maxValueForGraph = Math.max(root.manualMaxGraphValue, maxVal > 0 ? maxVal * 1.1 : root.manualMaxGraphValue);
        } else {
            root.maxValueForGraph = root.manualMaxGraphValue;
        }
    }

    // Full representation of the plasmoid
    fullRepresentation: Item {
        Layout.minimumWidth: 100
        Layout.minimumHeight: 80
        Layout.preferredWidth: 180
        Layout.preferredHeight: 140

        Rectangle {
            id: representationArea
            anchors.fill: parent
            color: root.showBackground ? root.bgColor : "transparent"
            border.color: root.showBackground ? Qt.rgba(1, 1, 1, 0.3) : "transparent"
            border.width: root.showBackground ? root.borderWidth : 0
            radius: root.cornerRadius

            Item {
                id: contentItem
                anchors.fill: parent
                anchors.margins: root.showBackground ? parent.border.width + 2 : 0
                clip: true

                // Dynamic font size based on widget height
                readonly property int baseFontSize: Math.max(7, Math.min(12, contentItem.height / 12))
                readonly property int titleFontSize: Math.max(8, Math.min(14, contentItem.height / 10))

                // Title label
                Text {
                    id: fbMeterTitleLabel
                    anchors.top: parent.top
                    anchors.topMargin: root.topBottomMarginForContent
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    text: "FB-Traffic-KDE"
                    font.family: "Monospace"
                    font.bold: true
                    font.pixelSize: contentItem.titleFontSize
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // Stats row with upload and download values
                RowLayout {
                    id: statsRowLayout
                    anchors.top: fbMeterTitleLabel.bottom
                    anchors.topMargin: root.labelSpacing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: root.labelSpacing

                    // Upload column
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            id: uploadIdentifierLabel
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: "▲ Up:"
                            font.family: "Monospace"
                            font.bold: true
                            font.pixelSize: contentItem.baseFontSize
                            color: root.uploadColor
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            id: uploadValueLabel
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: root.uploadValue
                            font.family: "Monospace"
                            font.bold: true
                            font.pixelSize: contentItem.baseFontSize
                            color: root.hasError ? root.loadingColor : root.uploadColor
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Download column
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            id: downloadIdentifierLabel
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: "▼ Down:"
                            font.family: "Monospace"
                            font.bold: true
                            font.pixelSize: contentItem.baseFontSize
                            color: root.downloadColor
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            id: downloadValueLabel
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: root.downloadValue
                            font.family: "Monospace"
                            font.bold: true
                            font.pixelSize: contentItem.baseFontSize
                            color: root.hasError ? root.loadingColor : root.downloadColor
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Combined graph canvas for both upload and download
                Canvas {
                    id: combinedGraph
                    anchors.top: statsRowLayout.bottom
                    anchors.topMargin: root.graphSpacing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.topBottomMarginForContent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2

                    onPaint: {
                        drawCombinedTrafficGraph(getContext("2d"), width, height, root.upHistory, root.downHistory, root.maxValueForGraph);
                    }

                    Connections {
                        target: root
                        function onUpHistoryChanged() { combinedGraph.requestPaint(); }
                        function onDownHistoryChanged() { combinedGraph.requestPaint(); }
                    }
                }
            }
        }
    }

    // Function to draw combined traffic graph with both upload and download
    function drawCombinedTrafficGraph(ctx, w, h, uploadHistory, downloadHistory, maxValue) {
        ctx.clearRect(0, 0, w, h);

        // Draw grid
        ctx.strokeStyle = "rgba(255, 255, 255, 0.25)";
        ctx.lineWidth = 1;

        if (root.gridCells > 0) {
            // Vertical lines
            for (var i = 0; i <= root.gridCells; i++) {
                var x = (w / root.gridCells) * i;
                if (i === root.gridCells) x = w;
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, h);
                ctx.stroke();
            }

            // Horizontal lines
            var horizontalGridCells = Math.max(1, Math.floor(root.gridCells / 2));
            for (var j = 0; j <= horizontalGridCells; j++) {
                var y = (h / horizontalGridCells) * j;
                if (j === horizontalGridCells) y = h;
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(w, y);
                ctx.stroke();
            }
        }

        // Draw download area first (behind upload)
        if (downloadHistory.length > 0) {
            ctx.beginPath();
            var firstXPos = 0;
            var firstRawValue = downloadHistory[0];
            var firstNormalizedValue = Math.max(0, Math.min(1, firstRawValue / maxValue));
            var firstYPos = h * (1 - firstNormalizedValue);
            ctx.moveTo(firstXPos, firstYPos);

            for (var k = 0; k < downloadHistory.length; k++) {
                var xPos = (k / (Math.max(1, root.maxPoints - 1))) * w;
                var rawValue = downloadHistory[k];
                var normalizedValue = Math.max(0, Math.min(1, rawValue / maxValue));
                var yPos = h * (1 - normalizedValue);
                ctx.lineTo(xPos, yPos);
            }

            var lastXPos = ((downloadHistory.length - 1) / (Math.max(1, root.maxPoints - 1))) * w;
            if (downloadHistory.length === 1) lastXPos = firstXPos;

            ctx.lineTo(lastXPos, h);
            ctx.lineTo(firstXPos, h);
            ctx.closePath();

            ctx.fillStyle = Qt.rgba(root.downloadColor.r, root.downloadColor.g, root.downloadColor.b, 0.5);
            ctx.fill();

            // Draw line on top
            ctx.strokeStyle = root.downloadColor;
            ctx.lineWidth = 1.5;
            ctx.beginPath();

            for (var m = 0; m < downloadHistory.length; m++) {
                var lineXPos = (m / (Math.max(1, root.maxPoints - 1))) * w;
                var lineRawValue = downloadHistory[m];
                var lineNormalizedValue = Math.max(0, Math.min(1, lineRawValue / maxValue));
                var lineYPos = h * (1 - lineNormalizedValue);
                if (m === 0) {
                    ctx.moveTo(lineXPos, lineYPos);
                } else {
                    ctx.lineTo(lineXPos, lineYPos);
                }
            }
            ctx.stroke();
        }

        // Draw upload area (in front)
        if (uploadHistory.length > 0) {
            ctx.beginPath();
            var upFirstXPos = 0;
            var upFirstRawValue = uploadHistory[0];
            var upFirstNormalizedValue = Math.max(0, Math.min(1, upFirstRawValue / maxValue));
            var upFirstYPos = h * (1 - upFirstNormalizedValue);
            ctx.moveTo(upFirstXPos, upFirstYPos);

            for (var n = 0; n < uploadHistory.length; n++) {
                var upXPos = (n / (Math.max(1, root.maxPoints - 1))) * w;
                var upRawValue = uploadHistory[n];
                var upNormalizedValue = Math.max(0, Math.min(1, upRawValue / maxValue));
                var upYPos = h * (1 - upNormalizedValue);
                ctx.lineTo(upXPos, upYPos);
            }

            var upLastXPos = ((uploadHistory.length - 1) / (Math.max(1, root.maxPoints - 1))) * w;
            if (uploadHistory.length === 1) upLastXPos = upFirstXPos;

            ctx.lineTo(upLastXPos, h);
            ctx.lineTo(upFirstXPos, h);
            ctx.closePath();

            ctx.fillStyle = Qt.rgba(root.uploadColor.r, root.uploadColor.g, root.uploadColor.b, 0.7);
            ctx.fill();

            // Draw line on top
            ctx.strokeStyle = root.uploadColor;
            ctx.lineWidth = 1.5;
            ctx.beginPath();

            for (var p = 0; p < uploadHistory.length; p++) {
                var upLineXPos = (p / (Math.max(1, root.maxPoints - 1))) * w;
                var upLineRawValue = uploadHistory[p];
                var upLineNormalizedValue = Math.max(0, Math.min(1, upLineRawValue / maxValue));
                var upLineYPos = h * (1 - upLineNormalizedValue);
                if (p === 0) {
                    ctx.moveTo(upLineXPos, upLineYPos);
                } else {
                    ctx.lineTo(upLineXPos, upLineYPos);
                }
            }
            ctx.stroke();
        }
    }
}
