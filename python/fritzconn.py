import sys
import configparser
from collections import deque

from PyQt5.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QLabel, QSystemTrayIcon,
    QMenu, QAction
)
from PyQt5.QtCore import QTimer, Qt, QPoint, QRect
from PyQt5.QtGui import QIcon, QColor, QPixmap, QPainter, QPen, QCursor

import pyqtgraph as pg
from fritzconnection.lib.fritzstatus import FritzStatus

# --- KONSTANTEN FÜR FARBEN ---
GREEN_UP = '#55ff55'  # GRÜN für Upload
LIGHT_BLUE_DOWN = '#66CCFF' # Helles Blau für Download
DARK_GREY = '#555555'
BORDER_COLOR = '#9a9a9a'
# -----------------------------


def build_tray_icon():
    pm = QPixmap(16, 16)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    p.setPen(QPen(QColor(GREEN_UP), 2))
    p.drawLine(3, 13, 8, 4); p.drawLine(8, 4, 13, 13)
    p.setPen(QPen(QColor(LIGHT_BLUE_DOWN), 2))
    p.drawLine(3, 3, 8, 12); p.drawLine(8, 12, 13, 3)
    p.end()
    return QIcon(pm)


class HoverPlotWidget(pg.PlotWidget):
    HOVER_DELAY_MS = 2000
    GRID_DIVS = 6
    def __init__(self):
        pg.setConfigOption('foreground', 'w')
        super().__init__()
        self.setBackground(DARK_GREY)
        self._grid_v = []; self._grid_h = []
        self.GRID_PEN = pg.mkPen(color=(200, 200, 200, 150), width=1)
        self.plotItem.hideAxis('left'); self.plotItem.hideAxis('bottom')
        self._hover_active = False
        cross_pen = pg.mkPen('#FFFFFF66', width=1)
        self.vLine = pg.InfiniteLine(angle=90, movable=False, pen=cross_pen)
        self.hLine = pg.InfiniteLine(angle=0, movable=False, pen=cross_pen)
        self.addItem(self.vLine, ignoreBounds=True); self.addItem(self.hLine, ignoreBounds=True)
        self.vLine.hide(); self.hLine.hide()
        self.info_text = pg.TextItem("", anchor=(0, 1), color='w'); self.addItem(self.info_text); self.info_text.hide()
        self.plotItem.vb.sigRangeChanged.connect(self._update_grid)
        self.proxy = pg.SignalProxy(self.scene().sigMouseMoved, rateLimit=60, slot=self._on_mouse_moved)
        self.setMouseTracking(True)
        self._hover_timer = QTimer(self); self._hover_timer.setSingleShot(True); self._hover_timer.timeout.connect(self._activate_hover)
        QTimer.singleShot(60, self._update_grid)

    def _clear_grid(self):
        for ln in self._grid_v + self._grid_h:
            try: self.removeItem(ln)
            except: pass
        self._grid_v.clear(); self._grid_h.clear()

    def _update_grid(self):
        (x_min, x_max), (y_min, y_max) = self.plotItem.vb.viewRange()
        if x_max <= x_min or y_max <= y_min: return
        self._clear_grid()
        for i in range(self.GRID_DIVS + 1):
            xv = x_min + (x_max - x_min) * i / self.GRID_DIVS
            ln = pg.InfiniteLine(angle=90, movable=False, pen=self.GRID_PEN); ln.setPos(xv)
            self.addItem(ln, ignoreBounds=True); self._grid_v.append(ln)
        for j in range(self.GRID_DIVS + 1):
            yv = y_min + (y_max - y_min) * j / self.GRID_DIVS
            ln = pg.InfiniteLine(angle=0, movable=False, pen=self.GRID_PEN); ln.setPos(yv)
            self.addItem(ln, ignoreBounds=True); self._grid_h.append(ln)

    def _activate_hover(self):
        self._hover_active = True
        self.plotItem.showAxis('left'); self.plotItem.showAxis('bottom')
        for ax_name in ('left', 'bottom'):
            ax = self.plotItem.getAxis(ax_name)
            ax.setStyle(showValues=True, tickLength=5); ax.setPen(pg.mkPen('#DDDDDD'))
        self.vLine.show(); self.hLine.show(); self.info_text.show()

    def _deactivate_hover(self):
        if self._hover_timer.isActive(): self._hover_timer.stop() 
        self._hover_active = False
        self.plotItem.hideAxis('left'); self.plotItem.hideAxis('bottom')
        self.vLine.hide(); self.hLine.hide(); self.info_text.hide()

    def enterEvent(self, e):
        if not self._hover_timer.isActive():
            self._hover_timer.start(self.HOVER_DELAY_MS)
        super().enterEvent(e)

    def leaveEvent(self, e):
        if self._hover_timer.isActive(): self._hover_timer.stop()
        if self._hover_active: self._deactivate_hover()
        super().leaveEvent(e)

    def _on_mouse_moved(self, evt):
        if not self._hover_active: return
        pos = evt[0]
        if not self.plotItem.sceneBoundingRect().contains(pos): return
        mp = self.plotItem.vb.mapSceneToView(pos)
        x, y = mp.x(), mp.y()
        self.vLine.setPos(x); self.hLine.setPos(y)
        vr = self.plotItem.viewRange()
        self.info_text.setPos(vr[0][0], vr[1][1])
        self.info_text.setText(f"x={x:.0f}  y={y:.2f}")


class TrafficMonitor(QWidget):
    MAX_POINTS = 120
    RESIZE_HANDLE_SIZE = 18

    def __init__(self, fritzbox):
        super().__init__()
        self.fritzbox = fritzbox
        self.upload_history = deque(maxlen=self.MAX_POINTS)
        self.download_history = deque(maxlen=self.MAX_POINTS)
        self.x_values = []
        self.counter = 0
        self.last_up = 0.0
        self.last_down = 0.0
        self._tray = None

        # Attribute für manuelle Resize/Drag-Logik
        self._resizing = False
        self._resize_origin = QPoint()
        self._start_geom = QRect()
        self._offset = QPoint() 

        self.initUI()
        self._setup_tray()

    def initUI(self):
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Tool)
        
        # Hintergrund und Rahmen für das Haupt-Widget entfernen
        self.setStyleSheet(f"background:{DARK_GREY}; border: none;")

        layout = QVBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0) 
        layout.setSpacing(0) 

        # 1. Rahmen-Container (Zeichnet das "n")
        self.title_frame = QWidget(self)
        self.title_frame.setFixedHeight(50)
        self.title_frame.setStyleSheet(f"""
            background: {DARK_GREY};
            border-top: 3px solid {BORDER_COLOR}; 
            border-left: 3px solid {BORDER_COLOR};
            border-right: 3px solid {BORDER_COLOR};
            border-bottom: none;
        """)

        # 2. Titel-Label (HTML-Text, sitzt im Frame)
        self.title_label = QLabel(self.title_frame)
        self.title_label.setAlignment(Qt.AlignCenter)
        
        # Inneres Layout für das Frame, um das Label zu zentrieren und den Rahmen freizuhalten
        frame_layout = QVBoxLayout(self.title_frame)
        frame_layout.setContentsMargins(0, 0, 0, 0)
        frame_layout.addWidget(self.title_label)
        
        # Das FRAME-Widget wird dem Haupt-Layout hinzugefügt
        layout.addWidget(self.title_frame) 

        # Plot-Widget
        self.plot_widget = HoverPlotWidget()
        # Rahmen für das "U" (Unten, Links, Rechts)
        self.plot_widget.setStyleSheet(f"""
            border-bottom: 3px solid {BORDER_COLOR}; 
            border-left: 3px solid {BORDER_COLOR};
            border-right: 3px solid {BORDER_COLOR};
            border-top: none; 
        """)
        layout.addWidget(self.plot_widget)

        self.plot_item = self.plot_widget.plotItem
        # Plot-Kurven mit den neuen Farben
        self.upload_curve = self.plot_widget.plot(pen=pg.mkPen(GREEN_UP, width=2))
        self.download_curve = self.plot_widget.plot(pen=pg.mkPen(LIGHT_BLUE_DOWN, width=2))

        self.setLayout(layout)
        self.timer = QTimer(self); self.timer.timeout.connect(self.update_traffic); self.timer.start(1000)
        self.resize(620, 320)
        self._update_title(0.0, 0.0)

    # --- DRAG-LOGIK AUF TITLE-FRAME (Rahmen-Container) ---
    def mousePressEvent(self, ev):
        if ev.button() == Qt.LeftButton:
            # Prüfen, ob der Klick auf dem Title-Frame war (Drag-Bereich)
            if self.title_frame.geometry().contains(ev.pos()):
                w = self.windowHandle()
                if w:
                    try:
                        w.startSystemMove()
                        return
                    except Exception:
                        pass
                # Fallback für manuelle Verschiebung
                self._offset = ev.globalPos() - self.frameGeometry().topLeft()
                ev.accept()
                return
            
        if ev.button() == Qt.LeftButton and self._in_resize_corner(ev.pos()):
            self._resizing = True
            self._resize_origin = ev.globalPos()
            self._start_geom = self.geometry()
            ev.accept()
            return
        super().mousePressEvent(ev)

    def mouseMoveEvent(self, ev):
        if not self._resizing and (ev.buttons() & Qt.LeftButton) and not self._offset.isNull():
            # Manuelles Verschieben
            self.move(ev.globalPos() - self._offset)
            ev.accept()
            return
            
        if self._resizing:
            diff = ev.globalPos() - self._resize_origin
            new_w = max(200, self._start_geom.width() + diff.x())
            new_h = max(100, self._start_geom.height() + diff.y())
            self.setGeometry(QRect(self._start_geom.topLeft(), QPoint(self._start_geom.left() + new_w, self._start_geom.top() + new_h)))
            ev.accept()
            return
            
        if self._in_resize_corner(ev.pos()):
            self.setCursor(Qt.SizeFDiagCursor)
        else:
            if self.cursor().shape() == Qt.SizeFDiagCursor:
                self.unsetCursor()

    def mouseReleaseEvent(self, ev):
        if ev.button() == Qt.LeftButton and self._resizing:
            self._resizing = False
        self._offset = QPoint() # Reset Drag offset
        super().mouseReleaseEvent(ev)
    # ---------------------------------
    
    def _calc_font_size(self, up, down):
        """Berechnet die Schriftgröße basierend auf der aktuellen Breite."""
        max_text_width = self.width() 
        base = 16
        min_fs = 10
        
        test_text = "Down: 999.99 kB/s" 
        
        fs = base
        for fs_test in range(base, min_fs - 1, -1):
            if len(test_text) * fs_test * 0.48 <= max_text_width - 10: 
                fs = fs_test
                break
        return fs


    def _update_title(self, up, down):
        """
        Aktualisiert den Titel-Text mit Zeilenumbruch und korrigierten Farben.
        """
        fs = self._calc_font_size(up, down)
        
        # Styling für das innere QLabel: Nur Schriftgröße und Padding
        self.title_label.setStyleSheet(f"""
            font-weight: bold;
            font-size: {fs}px;
            padding-top: 5px; 
        """)
        
        # HTML-Text mit Zeilenumbruch und Farben
        self.title_label.setText(
            f"<span style='color:{GREEN_UP};'>Up: {up:.2f} kB/s</span>"
            f"<br><span style='color:{LIGHT_BLUE_DOWN};'>Down: {down:.2f} kB/s</span>"
        )


    def _setup_tray(self):
        QApplication.instance().setQuitOnLastWindowClosed(False)
        if not QSystemTrayIcon.isSystemTrayAvailable():
            return
        self._tray = QSystemTrayIcon(build_tray_icon(), self)
        menu = QMenu()
        act_toggle = QAction("Anzeigen / Verstecken", self)
        act_quit = QAction("Beenden", self)
        act_toggle.triggered.connect(self._toggle_visible)
        act_quit.triggered.connect(self._quit)
        menu.addAction(act_toggle); menu.addSeparator(); menu.addAction(act_quit)
        self._tray.setContextMenu(menu)
        self._tray.activated.connect(self._tray_activated)
        self._tray.show()

    def _tray_activated(self, reason):
        if reason == QSystemTrayIcon.Trigger:
            self._toggle_visible()

    def _toggle_visible(self):
        if self.isVisible():
            self.hide()
        else:
            self.show(); self.raise_(); self.activateWindow()

    def _quit(self):
        QApplication.instance().quit()

    def resizeEvent(self, ev):
        super().resizeEvent(ev)
        self._update_title(self.last_up, self.last_down)
        
    def _in_resize_corner(self, pos):
        return (self.width() - pos.x() <= self.RESIZE_HANDLE_SIZE) and \
               (self.height() - pos.y() <= self.RESIZE_HANDLE_SIZE)

    def update_traffic(self):
        try:
            rates = self.fritzbox.transmission_rate
        except Exception as e:
            # Setze Fehlertext, falls Verbindung fehlschlägt
            self.title_label.setText(f"<span style='color:{GREEN_UP};'>Fehler:</span><br><span style='color:{LIGHT_BLUE_DOWN};'>{e}</span>")
            return
        
        up = rates[0] / 1024.0
        down = rates[1] / 1024.0
        
        self.last_up = up; self.last_down = down
        self._update_title(up, down)
        
        self.upload_history.append(up); self.download_history.append(down)
        self.counter += 1
        self.x_values = list(range(self.counter - len(self.upload_history) + 1, self.counter + 1))
        self.upload_curve.setData(self.x_values, list(self.upload_history))
        self.download_curve.setData(self.x_values, list(self.download_history))
        self.plot_widget.plotItem.enableAutoRange(axis=pg.ViewBox.XYAxes, enable=True)


def load_config(path='config.ini'):
    config = configparser.ConfigParser()
    if not config.read(path):
        raise FileNotFoundError(f"Konfigurationsdatei {path} nicht gefunden")
    address = config.get('credentials', 'address', fallback='fritz.box')
    password = config.get('credentials', 'password', fallback='')
    return address, password


if __name__ == "__main__":
    try:
        address, password = load_config()
        fritzbox = FritzStatus(address=address, password=password)
        app = QApplication(sys.argv)
        monitor = TrafficMonitor(fritzbox)
        monitor.show()
        sys.exit(app.exec_())
    except Exception as e:
        print(f"Error: {e}")
