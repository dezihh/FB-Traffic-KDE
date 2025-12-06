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
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    // Configuration properties with defaults
    property int refreshInterval: Plasmoid.configuration.refreshInterval || 10
    property bool autoScaleGraphs: Plasmoid.configuration.autoScaleGraphs !== false
    property real manualMaxGraphValue: Plasmoid.configuration.manualMaxGraphValue || 100.0

    // --- Graph data properties ---
    property var upHistory: []
    property var downHistory: []
    property int maxPoints: 50
    property real maxValueForUploadGraph: manualMaxGraphValue
    property real maxValueForDownloadGraph: manualMaxGraphValue

    // --- Display properties ---
    property string uploadValue: "Loading..."
    property string downloadValue: "Loading..."
    property bool hasError: false

    // --- Style properties ---
    property int borderWidth: 2
    property int topBottomMarginForContent: 5
    property int labelSpacing: 2
    property int graphSpacing: 5
    property int gridCells: 10
    property int cornerRadius: 8
    property int statsFontSize: 9

    // --- Colors ---
    property color uploadColor: "#4bb648"
    property color downloadColor: "#2fa1e8"
    property color loadingColor: "gray"
    property color bgColor: "transparent"

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

        // Auto-scale graphs if enabled
        if (root.autoScaleGraphs) {
            var maxUp = root.manualMaxGraphValue;
            for (var i = 0; i < root.upHistory.length; i++) {
                if (root.upHistory[i] > maxUp) maxUp = root.upHistory[i];
            }
            root.maxValueForUploadGraph = Math.max(root.manualMaxGraphValue, maxUp > 0 ? maxUp * 1.1 : root.manualMaxGraphValue);

            var maxDown = root.manualMaxGraphValue;
            for (var j = 0; j < root.downHistory.length; j++) {
                if (root.downHistory[j] > maxDown) maxDown = root.downHistory[j];
            }
            root.maxValueForDownloadGraph = Math.max(root.manualMaxGraphValue, maxDown > 0 ? maxDown * 1.1 : root.manualMaxGraphValue);
        } else {
            root.maxValueForUploadGraph = root.manualMaxGraphValue;
            root.maxValueForDownloadGraph = root.manualMaxGraphValue;
        }
    }

    // Full representation of the plasmoid
    fullRepresentation: Item {
        Layout.minimumWidth: 200
        Layout.minimumHeight: 230
        Layout.preferredWidth: 200
        Layout.preferredHeight: 230

        Rectangle {
            id: representationArea
            anchors.fill: parent
            color: root.bgColor
            border.color: "white"
            border.width: root.borderWidth
            opacity: 0.85
            radius: root.cornerRadius

            Item {
                id: contentItem
                anchors.fill: parent
                anchors.margins: parent.border.width
                clip: true

                readonly property int totalVerticalMarginsInContent: root.topBottomMarginForContent + root.labelSpacing + root.graphSpacing + root.topBottomMarginForContent
                readonly property real availableHeightForElements: height - totalVerticalMarginsInContent
                readonly property real titleAreaHeight: availableHeightForElements * 0.10
                readonly property real labelsAreaHeight: availableHeightForElements * 0.14
                readonly property real graphsTotalAreaHeight: availableHeightForElements * 0.76
                readonly property real individualGraphHeight: graphsTotalAreaHeight / 2

                // Title label
                Text {
                    id: fbMeterTitleLabel
                    anchors.top: parent.top
                    anchors.topMargin: root.topBottomMarginForContent
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: contentItem.titleAreaHeight
                    text: "FB-Traffic-KDE"
                    font.family: "Monospace"
                    font.bold: true
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
                    height: contentItem.labelsAreaHeight
                    spacing: root.labelSpacing

                    // Upload column
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            id: uploadIdentifierLabel
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: "▲ Up:"
                            font.family: "Monospace"
                            font.bold: true
                            font.pointSize: root.statsFontSize
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
                            font.pointSize: root.statsFontSize
                            color: root.hasError ? root.loadingColor : root.uploadColor
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Download column
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            id: downloadIdentifierLabel
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: "▼ Down:"
                            font.family: "Monospace"
                            font.bold: true
                            font.pointSize: root.statsFontSize
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
                            font.pointSize: root.statsFontSize
                            color: root.hasError ? root.loadingColor : root.downloadColor
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Upload graph canvas
                Canvas {
                    id: uploadGraph
                    anchors.top: statsRowLayout.bottom
                    anchors.topMargin: root.graphSpacing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: contentItem.individualGraphHeight

                    onPaint: {
                        drawTrafficGraph(getContext("2d"), width, height, root.upHistory, root.maxValueForUploadGraph, root.uploadColor);
                    }

                    Connections {
                        target: root
                        function onUpHistoryChanged() { uploadGraph.requestPaint(); }
                    }
                }

                // Download graph canvas
                Canvas {
                    id: downloadGraph
                    anchors.top: uploadGraph.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.topBottomMarginForContent

                    onPaint: {
                        drawTrafficGraph(getContext("2d"), width, height, root.downHistory, root.maxValueForDownloadGraph, root.downloadColor);
                    }

                    Connections {
                        target: root
                        function onDownHistoryChanged() { downloadGraph.requestPaint(); }
                    }
                }
            }
        }
    }

    // Function to draw traffic graph
    function drawTrafficGraph(ctx, w, h, history, maxValue, graphColor) {
        ctx.clearRect(0, 0, w, h);

        // Draw grid
        ctx.strokeStyle = "rgba(255, 255, 255, 0.4)";
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

        // Draw filled area
        if (history.length > 0) {
            ctx.beginPath();
            var firstXPos = 0;
            var firstRawValue = history[0];
            var firstNormalizedValue = Math.max(0, Math.min(1, firstRawValue / maxValue));
            var firstYPos = h * (1 - firstNormalizedValue);
            ctx.moveTo(firstXPos, firstYPos);

            for (var k = 0; k < history.length; k++) {
                var xPos = (k / (Math.max(1, root.maxPoints - 1))) * w;
                var rawValue = history[k];
                var normalizedValue = Math.max(0, Math.min(1, rawValue / maxValue));
                var yPos = h * (1 - normalizedValue);
                ctx.lineTo(xPos, yPos);
            }

            var lastXPos = ((history.length - 1) / (Math.max(1, root.maxPoints - 1))) * w;
            if (history.length === 1) lastXPos = firstXPos;

            ctx.lineTo(lastXPos, h);
            ctx.lineTo(firstXPos, h);
            ctx.closePath();

            ctx.fillStyle = Qt.rgba(graphColor.r, graphColor.g, graphColor.b, 1.0);
            ctx.fill();

            // Draw line on top
            ctx.strokeStyle = graphColor;
            ctx.lineWidth = 1;
            ctx.beginPath();

            for (var m = 0; m < history.length; m++) {
                var lineXPos = (m / (Math.max(1, root.maxPoints - 1))) * w;
                var lineRawValue = history[m];
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
    }
}
