#!/usr/bin/env python3
"""
Traffic.py: Ruft Traffic-Daten (Upload/Download-Raten) von einer AVM Fritz!Box ab
und gibt sie im JSON-Format aus.

Dieses Skript wird typischerweise von einem Plasmoid oder einem anderen Monitoring-Tool
aufgerufen, um die Netzwerkaktivität der Fritz!Box anzuzeigen.
"""

import sys
import os
import time
import json
import configparser
from fritzconnection import FritzConnection # Bibliothek zur Kommunikation mit der Fritz!Box

# --- Globale Konfigurationen und Konstanten ---
CONFIG_FILE_NAME = "fritzplasmoid.ini"
STATE_FILE_NAME = "fritz_traffic_state.json"

# Pfad zur Konfigurationsdatei im Benutzerverzeichnis
CONFIG_PATH = os.path.join(os.path.expanduser("~/.config"), CONFIG_FILE_NAME)
# Pfad zur Zustandsdatei im Cache-Verzeichnis des Benutzers
STATE_FILE_PATH = os.path.join(os.path.expanduser("~/.cache"), STATE_FILE_NAME)

DEFAULT_HOST = "fritz.box" # Standard-Hostname der Fritz!Box
CONNECTION_TIMEOUT = 5 # Sekunden Timeout für die Verbindung

def load_configuration(config_path):
    """Lädt die Konfiguration (Passwort, Host) aus der INI-Datei."""
    cfg = configparser.ConfigParser()
    if not os.path.exists(config_path):
        # Gibt einen Fehler im JSON-Format aus, wenn die Konfigurationsdatei nicht existiert.
        print(json.dumps({"upload": "NoCfg", "download": "NoCfg", "error": f"Config file not found: {config_path}"}))
        sys.exit(1)
    cfg.read(config_path)

    try:
        password = cfg["credentials"]["password"]
        host = cfg["credentials"].get("host", DEFAULT_HOST) # .get() um Fallback auf Default Host zu ermöglichen
        return password, host
    except KeyError:
        # Gibt einen Fehler aus, wenn die Sektion 'credentials' oder der Schlüssel 'password' fehlt.
        print(json.dumps({"upload": "CfgKeyErr", "download": "CfgKeyErr", "error": "Missing 'password' or 'credentials' section in config"}))
        sys.exit(1)
    except Exception as e:
        # Fängt andere mögliche Fehler beim Lesen der Konfiguration ab.
        print(json.dumps({"upload": "CfgReadErr", "download": "CfgReadErr", "error": f"Config read error: {str(e)}"}))
        sys.exit(1)

def connect_to_fritzbox(host, password):
    """Stellt die Verbindung zur Fritz!Box her."""
    try:
        fc = FritzConnection(address=host, password=password, timeout=CONNECTION_TIMEOUT)
        return fc
    except Exception as e:
        # Gibt einen Verbindungsfehler aus.
        print(json.dumps({"upload": "ConErr", "download": "ConErr", "error": f"Connection failed: {str(e)}"}))
        sys.exit(1)

def get_traffic_stats(fc):
    """Ruft die Gesamtanzahl gesendeter und empfangener Bytes ab."""
    try:
        # Neuere Fritz!OS-Versionen (ca. >7.2x) verwenden oft 'WANCommonInterfaceConfig1'
        # und die 'X_AVM_DE_TotalBytesSent64'-Zähler für 64-Bit-Werte, um Überläufe zu vermeiden.
        try:
            status_info = fc.call_action("WANCommonInterfaceConfig1", "GetCommonLinkProperties")
            # Die Keys können je nach Fritz!OS-Version leicht variieren.
            # Hier wird versucht, die gängigsten Keys für 64-Bit-Zähler zu verwenden.
            sent_key = "NewX_AVM_DE_TotalBytesSent64" if "NewX_AVM_DE_TotalBytesSent64" in status_info else "NewTotalBytesSent" # Fallback
            recv_key = "NewX_AVM_DE_TotalBytesReceived64" if "NewX_AVM_DE_TotalBytesReceived64" in status_info else "NewTotalBytesReceived" # Fallback
            sent = status_info[sent_key]
            recv = status_info[recv_key]
        except Exception:
            # Fallback für ältere Fritz!OS-Versionen oder falls der obige Service/Action nicht verfügbar ist.
            sent = fc.call_action("WANCommonIFC1", "GetTotalBytesSent")["NewTotalBytesSent"]
            recv = fc.call_action("WANCommonIFC1", "GetTotalBytesReceived")["NewTotalBytesReceived"]
        return float(sent), float(recv) # Konvertierung zu float für Berechnungen
    except Exception as e:
        # Gibt einen API-Fehler aus, wenn Daten nicht abgerufen werden konnten.
        print(json.dumps({"upload": "APIErr", "download": "APIErr", "error": f"API call failed: {str(e)}"}))
        sys.exit(1)

def load_previous_state(state_file_path):
    """Lädt den vorherigen Zustand (gesendete/empfangene Bytes, Zeitstempel) aus der Zustandsdatei."""
    prev_data = {"sent": 0.0, "recv": 0.0, "time": 0.0} # Standardwerte, falls keine Datei existiert
    if os.path.exists(state_file_path):
        try:
            with open(state_file_path, "r") as f:
                prev_data = json.load(f)
                # Sicherstellen, dass alle erwarteten Keys vorhanden sind und numerisch sind
                prev_data["sent"] = float(prev_data.get("sent", 0.0))
                prev_data["recv"] = float(prev_data.get("recv", 0.0))
                prev_data["time"] = float(prev_data.get("time", 0.0))
        except (IOError, json.JSONDecodeError, ValueError) as e:
            # Bei Fehlern (Datei nicht lesbar, kein valides JSON, Wert nicht numerisch)
            # werden die Standardwerte verwendet und der Fehler wird nicht weiter behandelt,
            # da das Skript beim nächsten Mal eine neue Zustandsdatei anlegen kann.
            # Optional: Hier könnte man den Fehler loggen, falls gewünscht.
            pass
    return prev_data

def save_current_state(state_file_path, current_sent, current_recv, timestamp):
    """Speichert den aktuellen Zustand in der Zustandsdatei."""
    try:
        # Sicherstellen, dass das Cache-Verzeichnis existiert
        os.makedirs(os.path.dirname(state_file_path), exist_ok=True)
        with open(state_file_path, "w") as f:
            json.dump({"sent": current_sent, "recv": current_recv, "time": timestamp}, f)
    except IOError as e:
        # Fehler beim Schreiben der Zustandsdatei. Dies ist nicht kritisch für den aktuellen Lauf,
        # aber der nächste Lauf wird keine korrekten Deltas berechnen können.
        # Optional: Hier könnte man den Fehler loggen.
        pass

def main():
    """Hauptfunktion des Skripts."""
    password, host = load_configuration(CONFIG_PATH)
    fc = connect_to_fritzbox(host, password)
    current_sent_bytes, current_recv_bytes = get_traffic_stats(fc)
    prev_state = load_previous_state(STATE_FILE_PATH)

    now_timestamp = time.time()

    # Zeitdifferenz seit dem letzten Abruf berechnen
    delta_time = now_timestamp - prev_state.get("time", now_timestamp) # .get() für sicheren Zugriff

    # Wenn delta_time 0 oder negativ ist (z.B. erster Lauf, Systemzeitänderung),
    # oder wenn die vorherige Zeit ungültig war, wird delta_time auf 1 gesetzt,
    # um eine Division durch Null zu vermeiden. Die Rate wird dann effektiv 0 für diesen Lauf sein,
    # wenn die Byte-Zähler gleich geblieben sind.
    if delta_time <= 0:
        delta_time = 1.0

    # Raten in kB/s berechnen
    # (aktuelle Bytes - vorherige Bytes) / Zeitdifferenz in Sekunden / 1024 (für kB)
    rate_up = (current_sent_bytes - prev_state.get("sent", current_sent_bytes)) / delta_time / 1024.0
    rate_down = (current_recv_bytes - prev_state.get("recv", current_recv_bytes)) / delta_time / 1024.0

    # Sicherstellen, dass keine negativen Raten ausgegeben werden.
    # Negative Raten können auftreten, wenn die Fritz!Box neu gestartet wurde
    # oder die Zähler aus anderen Gründen zurückgesetzt wurden.
    if rate_up < 0:
        rate_up = 0.00
    if rate_down < 0:
        rate_down = 0.00

    save_current_state(STATE_FILE_PATH, current_sent_bytes, current_recv_bytes, now_timestamp)

    # Daten im JSON-Format ausgeben, gerundet auf zwei Nachkommastellen
    output_data = {
        "upload": round(rate_up, 2),
        "download": round(rate_down, 2),
        "timestamp": now_timestamp # Zeitstempel der aktuellen Messung
    }
    print(json.dumps(output_data))

if __name__ == "__main__":
    main()
