// Importe der notwendigen Qt Quick und Plasma Module
import QtQuick 2.0
import QtQuick.Controls 2.0 // Für UI-Steuerelemente (obwohl hier nicht direkt genutzt, oft Standard)
import org.kde.plasma.plasmoid 2.0 // Basis für Plasma-Plasmoiden
import org.kde.plasma.core 2.0 as PlasmaCore // Kernkomponenten von Plasma, z.B. DataSource
import QtQuick.Layouts 1.12 // Für RowLayout und ColumnLayout

// Haupt-Item des Plasmoids
Item {
    id: root // Eindeutige ID für das Wurzelelement

    // Standardbreite und -höhe des Plasmoids
    width: 200
    height: 230

    // --- Eigenschaften für die Graphen-Daten ---
    property var upHistory: [] // Array zur Speicherung der Upload-Datenhistorie für den Graphen
    property var downHistory: [] // Array zur Speicherung der Download-Datenhistorie für den Graphen
    property int maxPoints: 50 // Maximale Anzahl von Datenpunkten, die im Graphen angezeigt werden
    property real maxValueForUploadGraph: manualMaxGraphValue // Maximalwert für die Y-Achse des Upload-Graphen
    property real maxValueForDownloadGraph: manualMaxGraphValue // Maximalwert für die Y-Achse des Download-Graphen

    // --- Eigenschaften für das Erscheinungsbild ---
    property int borderWidth: 2 // Breite des Rahmens um das Plasmoid
    property int topBottomMarginForContent: 5 // Oberer und unterer Innenabstand für den Inhalt
    property int labelSpacing: 2 // Abstand zwischen Labels oder Layoutelementen
    property int graphSpacing: 5 // Vertikaler Abstand zwischen den Labels und dem ersten Graphen
    property int gridCells: 10 // Anzahl der vertikalen Gitterlinien in den Graphen
    property int cornerRadius: 8 // Radius für abgerundete Ecken des Plasmoids
    property int statsFontSize: 9 // Schriftgröße für die Upload/Download-Textanzeigen

    // --- Konfigurationseigenschaften ---
    property bool autoScaleGraphs: true // Aktiviert/Deaktiviert die automatische Skalierung der Graphen
    property real manualMaxGraphValue: 100.0 // Manueller Maximalwert für Graphen, wenn autoScaleGraphs=false oder als Mindestwert bei Auto-Skalierung

    // --- Farbdefinitionen ---
    property color uploadColor: "#4bb648" // Farbe für Upload-Anzeigen (Text und Graph)
    property color downloadColor: "#2fa1e8" // Farbe für Download-Anzeigen (Text und Graph)
    property color loadingColor: "gray" // Farbe für den "Loading..." Text

    // Die volle Darstellung des Plasmoids (was der Benutzer sieht)
    Plasmoid.fullRepresentation: Rectangle {
        id: representationArea
        anchors.fill: parent // Füllt das Elternelement (root) aus
        color: "transparent" // Hintergrundfarbe des Rechtecks (durchsichtig)
        border.color: "white" // Farbe des Rahmens
        border.width: root.borderWidth // Breite des Rahmens, gebunden an die root-Eigenschaft
        opacity: 0.85 // Transparenz des Plasmoids
        radius: root.cornerRadius // Abgerundete Ecken, gebunden an die root-Eigenschaft

        // Inneres Item, das den Inhalt beschneidet und als Basis für weitere Elemente dient
        Item {
            id: contentItem
            anchors.fill: parent // Füllt den representationArea-Bereich aus
            anchors.margins: parent.border.width // Innenabstand entsprechend der Rahmenbreite
            clip: true // Inhalt wird an den Grenzen dieses Items abgeschnitten

            // --- Read-only Eigenschaften zur dynamischen Höhenberechnung ---
            // Gesamter vertikaler Abstand, der durch Margins und Spacing eingenommen wird
            readonly property int totalVerticalMarginsInContent: root.topBottomMarginForContent + root.labelSpacing + root.graphSpacing + root.topBottomMarginForContent
            // Verfügbare Höhe für die UI-Elemente nach Abzug der Margins
            readonly property real availableHeightForElements: height - totalVerticalMarginsInContent

            // Relative Höhenzuweisungen für die verschiedenen Bereiche
            readonly property real titleAreaHeight: contentItem.availableHeightForElements * 0.10 // 10% für den Titel
            readonly property real labelsAreaHeight: contentItem.availableHeightForElements * 0.14 // 14% für die Up/Down-Textanzeigen
            readonly property real graphsTotalAreaHeight: contentItem.availableHeightForElements * 0.76 // 76% für beide Graphen zusammen
            readonly property real individualGraphHeight: graphsTotalAreaHeight / 2 // Höhe eines einzelnen Graphen

            // Label für den Titel "FB-Meter"
            Label {
                id: fbMeterTitleLabel
                anchors.top: parent.top // Oben am contentItem verankert
                anchors.topMargin: root.topBottomMarginForContent // Mit oberem Innenabstand
                anchors.horizontalCenter: parent.horizontalCenter // Horizontal zentriert
                width: parent.width // Volle Breite des contentItem
                height: titleAreaHeight // Höhe basierend auf der prozentualen Zuweisung
                text: "FB-Traffic-KDE"
                font.family: "Monospace" // Monospace-Schriftart
                font.bold: true // Fettschrift
                color: "white" // Textfarbe
                horizontalAlignment: Text.AlignHCenter // Text horizontal zentrieren
                verticalAlignment: Text.AlignVCenter // Text vertikal zentrieren
            }

            // RowLayout für die nebeneinanderliegenden Upload- und Download-Anzeigen
            RowLayout {
                id: statsRowLayout
                anchors.top: fbMeterTitleLabel.bottom // Unterhalb des Titels
                anchors.topMargin: root.labelSpacing // Mit Abstand zum Titel
                anchors.left: parent.left // Links am contentItem
                anchors.right: parent.right // Rechts am contentItem
                height: labelsAreaHeight // Höhe basierend auf der prozentualen Zuweisung
                spacing: root.labelSpacing // Horizontaler Abstand zwischen den Spalten (Upload/Download)

                // Spaltenlayout für die Upload-Anzeige (Symbol + Wert)
                ColumnLayout {
                    Layout.fillWidth: true // Nimmt die Hälfte der verfügbaren Breite im RowLayout ein
                    spacing: 1 // Minimaler vertikaler Abstand zwischen Symbol und Wert

                    Label {
                        id: uploadIdentifierLabel // Label für das Upload-Symbol und Text
                        Layout.fillWidth: true // Volle Breite der Spalte
                        Layout.alignment: Qt.AlignHCenter // Inhalt horizontal zentrieren
                        text: "\u25B2 Up:" // Unicode-Dreieck nach oben + "Up:"
                        font.family: "Monospace"
                        font.bold: true
                        font.pointSize: root.statsFontSize // Schriftgröße
                        color: root.uploadColor // Farbe für Upload
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        id: uploadValueLabel // Label für den Upload-Wert
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        text: "Loading..." // Initialer Text
                        font.family: "Monospace"
                        font.bold: true
                        font.pointSize: root.statsFontSize
                        color: root.loadingColor // Initial graue Farbe
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Spaltenlayout für die Download-Anzeige (Symbol + Wert)
                ColumnLayout {
                    Layout.fillWidth: true // Nimmt die andere Hälfte der Breite ein
                    spacing: 1

                    Label {
                        id: downloadIdentifierLabel // Label für das Download-Symbol und Text
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        text: "\u25BC Down:" // Unicode-Dreieck nach unten + "Down:"
                        font.family: "Monospace"
                        font.bold: true
                        font.pointSize: root.statsFontSize
                        color: root.downloadColor // Farbe für Download
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        id: downloadValueLabel // Label für den Download-Wert
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        text: "Loading..." // Initialer Text
                        font.family: "Monospace"
                        font.bold: true
                        font.pointSize: root.statsFontSize
                        color: root.loadingColor // Initial graue Farbe
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Canvas zum Zeichnen des Upload-Graphen
            Canvas {
                id: uploadGraph
                anchors.top: statsRowLayout.bottom // Unterhalb der Textanzeigen
                anchors.topMargin: root.graphSpacing // Mit Abstand
                anchors.left: parent.left
                anchors.right: parent.right
                height: contentItem.individualGraphHeight // Höhe eines einzelnen Graphen

                // Wird aufgerufen, wenn der Canvas neu gezeichnet werden muss
                onPaint: {
                    var ctx = getContext("2d"); // 2D-Zeichenkontext holen
                    ctx.clearRect(0, 0, width, height); // Vorherigen Inhalt löschen
                    ctx.strokeStyle = "rgba(255, 255, 255, 0.4)"; // Farbe für Gitterlinien (halbtransparent weiß)
                    ctx.lineWidth = 1; // Linienbreite für Gitter

                    // Gitter zeichnen, falls gridCells > 0
                    if (root.gridCells > 0) {
                        // Vertikale Gitterlinien
                        for (var i = 0; i <= root.gridCells; i++) {
                            var x = (width / root.gridCells) * i;
                            if (i === root.gridCells) x = width; // Sicherstellen, dass die letzte Linie genau am Rand ist
                            ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                        }
                        // Horizontale Gitterlinien (halb so viele wie vertikale für bessere Optik)
                        let horizontalGridCells = Math.max(1, Math.floor(root.gridCells / 2));
                        for (var i = 0; i <= horizontalGridCells; i++) {
                            var y = (height / horizontalGridCells) * i;
                            if (i === horizontalGridCells) y = height; // Sicherstellen, dass die letzte Linie genau am Rand ist
                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                        }
                    }

                    // Upload-Graph zeichnen (gefüllter Bereich)
                    ctx.beginPath(); // Neuen Pfad beginnen
                    var firstXPos = 0;
                    if (root.upHistory.length > 0) {
                        // Startpunkt des Graphen
                        firstXPos = (0 / (Math.max(1, root.maxPoints -1))) * width; // X-Position des ersten Punkts
                        let firstRawValue = root.upHistory[0]; // Erster Datenwert
                        // Normalisierung des Werts auf den Bereich 0-1 bezogen auf maxValueForUploadGraph
                        let firstNormalizedValue = Math.max(0, Math.min(1, firstRawValue / root.maxValueForUploadGraph));
                        let firstYPos = height * (1 - firstNormalizedValue); // Y-Position (invertiert, da Canvas-Y von oben nach unten wächst)
                        ctx.moveTo(firstXPos, firstYPos); // Zum Startpunkt bewegen

                        // Linien zu den folgenden Punkten zeichnen
                        for (var i = 0; i < root.upHistory.length; ++i) {
                            let xPos = (i / (Math.max(1, root.maxPoints -1))) * width;
                            let rawValue = root.upHistory[i];
                            let normalizedValue = Math.max(0, Math.min(1, rawValue / root.maxValueForUploadGraph));
                            let yPos = height * (1 - normalizedValue);
                            ctx.lineTo(xPos, yPos);
                        }
                        // Pfad schließen, um eine Fläche zu bilden
                        let lastXPos = ((root.upHistory.length -1) / (Math.max(1, root.maxPoints -1))) * width;
                        if (root.upHistory.length === 1) lastXPos = firstXPos; // Falls nur ein Punkt da ist

                        ctx.lineTo(lastXPos, height); // Linie zum unteren Rand
                        ctx.lineTo(firstXPos, height); // Linie zum unteren Rand am Startpunkt
                        ctx.closePath(); // Pfad schließen
                    }
                    // Fläche füllen
                    ctx.fillStyle = Qt.rgba(root.uploadColor.r, root.uploadColor.g, root.uploadColor.b, 1.0); // Füllfarbe (Upload-Farbe)
                    ctx.fill();

                    // Upload-Graph zeichnen (Linie oben auf dem gefüllten Bereich)
                    ctx.strokeStyle = root.uploadColor; // Linienfarbe (Upload-Farbe)
                    ctx.lineWidth = 1; // Linienbreite
                    ctx.beginPath();
                    if (root.upHistory.length > 0) {
                        for (var i = 0; i < root.upHistory.length; ++i) {
                            let xPos = (i / (Math.max(1, root.maxPoints -1))) * width;
                            let rawValue = root.upHistory[i];
                            let normalizedValue = Math.max(0, Math.min(1, rawValue / root.maxValueForUploadGraph));
                            let yPos = height * (1 - normalizedValue);
                            if (i === 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
                        }
                    }
                    ctx.stroke(); // Linie zeichnen
                }
            }

            // Canvas zum Zeichnen des Download-Graphen (analog zum Upload-Graphen)
            Canvas {
                id: downloadGraph
                anchors.top: uploadGraph.bottom // Unterhalb des Upload-Graphen
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom // Bis zum unteren Rand des contentItem
                anchors.bottomMargin: root.topBottomMarginForContent // Mit unterem Innenabstand

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = "rgba(255, 255, 255, 0.4)";
                    ctx.lineWidth = 1;

                    if (root.gridCells > 0) {
                        for (var i = 0; i <= root.gridCells; i++) {
                            var x = (width / root.gridCells) * i;
                            if (i === root.gridCells) x = width;
                            ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                        }
                        let horizontalGridCells = Math.max(1, Math.floor(root.gridCells / 2));
                        for (var i = 0; i <= horizontalGridCells; i++) {
                            var y = (height / horizontalGridCells) * i;
                            if (i === horizontalGridCells) y = height;
                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                        }
                    }

                    ctx.beginPath();
                    var firstXPos = 0;
                    if (root.downHistory.length > 0) {
                        firstXPos = (0 / (Math.max(1, root.maxPoints -1))) * width;
                        let firstRawValue = root.downHistory[0];
                        let firstNormalizedValue = Math.max(0, Math.min(1, firstRawValue / root.maxValueForDownloadGraph));
                        let firstYPos = height * (1 - firstNormalizedValue);
                        ctx.moveTo(firstXPos, firstYPos);

                        for (var i = 0; i < root.downHistory.length; ++i) {
                            let xPos = (i / (Math.max(1, root.maxPoints -1))) * width;
                            let rawValue = root.downHistory[i];
                            let normalizedValue = Math.max(0, Math.min(1, rawValue / root.maxValueForDownloadGraph));
                            let yPos = height * (1 - normalizedValue);
                            ctx.lineTo(xPos, yPos);
                        }
                        let lastXPos = ((root.downHistory.length -1) / (Math.max(1, root.maxPoints -1))) * width;
                        if (root.downHistory.length === 1) lastXPos = firstXPos;

                        ctx.lineTo(lastXPos, height);
                        ctx.lineTo(firstXPos, height);
                        ctx.closePath();
                    }
                    ctx.fillStyle = Qt.rgba(root.downloadColor.r, root.downloadColor.g, root.downloadColor.b, 1.0); // Füllfarbe (Download-Farbe)
                    ctx.fill();

                    ctx.strokeStyle = root.downloadColor; // Linienfarbe (Download-Farbe)
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    if (root.downHistory.length > 0) {
                        for (var i = 0; i < root.downHistory.length; ++i) {
                            let xPos = (i / (Math.max(1, root.maxPoints -1))) * width;
                            let rawValue = root.downHistory[i];
                            let normalizedValue = Math.max(0, Math.min(1, rawValue / root.maxValueForDownloadGraph));
                            let yPos = height * (1 - normalizedValue);
                            if (i === 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
                        }
                    }
                    ctx.stroke();
                }
            }
        }

        // PlasmaCore.DataSource zum Abrufen von Daten von einem externen Skript
        PlasmaCore.DataSource {
            id: trafficSource
            engine: "executable" // Definiert, dass ein ausführbares Skript verwendet wird
            interval: 10000 // Intervall in Millisekunden für das Abrufen neuer Daten (hier: 10 Sekunden)

            // Wird aufgerufen, wenn neue Daten vom Skript empfangen werden
            onNewData: {
                // Prüfen, ob stdout-Daten vorhanden sind
                if (!data["stdout"]) {
                    uploadValueLabel.text = "Error";
                    uploadValueLabel.color = root.loadingColor; // Bei Fehler wieder auf Grau setzen
                    downloadValueLabel.text = "Error";
                    downloadValueLabel.color = root.loadingColor;
                    return; // Funktion beenden
                }
                try {
                    // Daten (erwartet als JSON-String) parsen
                    let obj = JSON.parse(data["stdout"]);

                    // Upload- und Download-Labels mit den neuen Werten und Einheiten aktualisieren
                    uploadValueLabel.text = obj.upload + " kB/s";
                    uploadValueLabel.color = root.uploadColor; // Farbe auf Upload-Farbe setzen
                    downloadValueLabel.text = obj.download + " kB/s";
                    downloadValueLabel.color = root.downloadColor; // Farbe auf Download-Farbe setzen

                    // Numerischen Wert für den Upload-Graphen extrahieren und Historie aktualisieren
                    let uploadString = String(obj.upload).replace(",", "."); // Komma durch Punkt ersetzen
                    let uploadMatch = uploadString.match(/[\d\.]+/); // Nur Zahlen und Punkte extrahieren
                    let cuRaw = uploadMatch ? parseFloat(uploadMatch[0]) : NaN; // In Zahl umwandeln
                    root.upHistory.push(isNaN(cuRaw) ? 0 : cuRaw); // Zur Historie hinzufügen (0 bei Fehler)
                    if (root.upHistory.length > root.maxPoints) root.upHistory.shift(); // Ältesten Wert entfernen, wenn maxPoints erreicht

                    // Skalierung für den Upload-Graphen anpassen, falls autoScaleGraphs aktiv ist
                    if (root.autoScaleGraphs) {
                        let maxUp = 0;
                        for (var i = 0; i < root.upHistory.length; ++i) {
                            if (root.upHistory[i] > maxUp) maxUp = root.upHistory[i];
                        }
                        // Maximalwert des Graphen auf das Maximum der Historie (plus 10% Puffer)
                        // oder auf manualMaxGraphValue setzen, je nachdem, was größer ist.
                        root.maxValueForUploadGraph = Math.max(root.manualMaxGraphValue, maxUp > 0 ? maxUp * 1.1 : root.manualMaxGraphValue);
                    } else {
                        root.maxValueForUploadGraph = root.manualMaxGraphValue; // Manuellen Wert verwenden
                    }
                    uploadGraph.requestPaint(); // Neuzeichnen des Upload-Graphen anfordern

                    // Analog für den Download-Graphen
                    let downloadString = String(obj.download).replace(",", ".");
                    let downloadMatch = downloadString.match(/[\d\.]+/);
                    let cdRaw = downloadMatch ? parseFloat(downloadMatch[0]) : NaN;
                    root.downHistory.push(isNaN(cdRaw) ? 0 : cdRaw);
                    if (root.downHistory.length > root.maxPoints) root.downHistory.shift();

                    if (root.autoScaleGraphs) {
                        let maxDown = 0;
                        for (var i = 0; i < root.downHistory.length; ++i) {
                            if (root.downHistory[i] > maxDown) maxDown = root.downHistory[i];
                        }
                        root.maxValueForDownloadGraph = Math.max(root.manualMaxGraphValue, maxDown > 0 ? maxDown * 1.1 : root.manualMaxGraphValue);
                    } else {
                        root.maxValueForDownloadGraph = root.manualMaxGraphValue;
                    }
                    downloadGraph.requestPaint(); // Neuzeichnen des Download-Graphen anfordern

                } catch (e) { // Fehlerbehandlung beim Parsen von JSON
                    uploadValueLabel.text = "ParseErr";
                    uploadValueLabel.color = root.loadingColor;
                    downloadValueLabel.text = "ParseErr";
                    downloadValueLabel.color = root.loadingColor;
                    // Historie im Fehlerfall mit 0 füllen, um Probleme mit NaN im Graphen zu vermeiden
                    root.upHistory.push(0); if (root.upHistory.length > root.maxPoints) root.upHistory.shift();
                    root.downHistory.push(0); if (root.downHistory.length > root.maxPoints) root.downHistory.shift();
                    uploadGraph.requestPaint();
                    downloadGraph.requestPaint();
                }
            }

            // Wird aufgerufen, wenn die Komponente vollständig geladen ist
            Component.onCompleted: {
                // Verbindung zum Python-Skript herstellen.
                // plasmoid.file("") gibt den Pfad zum Verzeichnis des Plasmoids zurück.
                // Der Pfad zum Skript muss entsprechend angepasst werden (hier: "code/Hugo.py" im Plasmoid-Verzeichnis).
                connectSource("python3 " + plasmoid.file("") +  "code/Traffic.py")
            }
        }
    }
}
