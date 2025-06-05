import QtQuick 2.0
import QtQuick.Layouts 1.1
import org.kde.plasma.components 3.0 as PlasmaComponents

Item {
    id: root
    width: parent.width
    //width: 220
    Layout.preferredHeight: 340
    Layout.fillWidth: true

    property string uploadValue: "0.00 kB/s"
    property string downloadValue: "0.00 kB/s"
    property var upHistory: []
    property var downHistory: []
    property int maxPoints: 50

    Rectangle {
        anchors.fill: parent
        color: "#222933"
        border.color: "#5a5a5a"
        radius: 6
        opacity: 0.2
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 1

        PlasmaComponents.Label {
                text: "\u25B2 Up: " + root.uploadValue
                color: "#4bb648"
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.Right
        }
        PlasmaComponents.Label {
                text: "\u25BC Down: " + root.downloadValue
                color: "#2fa1e8"
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter

        }

        Canvas {
            id: upGraph
            height: 60
            width: parent.width
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.strokeStyle = "#4bb648";
                ctx.beginPath();
                for (var i = 0; i < upHistory.length; ++i) {
                    let x = i * width / maxPoints;
                    let y = height * (1 - upHistory[i]);
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.stroke();
            }
        }
        Canvas {
            id: downGraph
            height: 60
            width: parent.width
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.strokeStyle = "#2fa1e8";
                ctx.beginPath();
                for (var i = 0; i < downHistory.length; ++i) {
                    let x = i * width / maxPoints;
                    let y = height * (1 - downHistory[i]);
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.stroke();
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "http://knx.ziegler-eu.de/cgi-bin/fritz.py?t=" + Date.now());
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText);
                    root.uploadValue = data.upload || "0.00 kB/s";
                    root.downloadValue = data.download || "0.00 kB/s";
                    function parseVal(val) {
                        if (!val) return 0;
                        var num = val.replace(/[^\d,\.]/g, "").replace(",", ".");
                        return parseFloat(num) || 0;
                    }
                    let up = parseVal(root.uploadValue);
                    let down = parseVal(root.downloadValue);
                    let upNorm = Math.min(up / 10.0, 1.0);
                    let downNorm = Math.min(down / 10.0, 1.0);
                    root.upHistory.push(upNorm);
                    root.downHistory.push(downNorm);
                    if (root.upHistory.length > root.maxPoints) root.upHistory.shift();
                    if (root.downHistory.length > root.maxPoints) root.downHistory.shift();
                    upGraph.requestPaint();
                    downGraph.requestPaint();
                }
            }
            xhr.send();
        }
    }
}
