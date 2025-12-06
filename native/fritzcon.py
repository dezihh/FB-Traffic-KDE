#!/usr/bin/env /home/dezi/.venv/bin/python
##!/usr/bin/env python3
import sys, os, signal, configparser
from collections import deque

from PyQt5.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QLabel, QSystemTrayIcon,
    QMenu, QAction
)
from PyQt5.QtCore import (
    QTimer, Qt, QPoint, QRect, QSettings, QByteArray
)
from PyQt5.QtGui import QIcon, QColor, QPixmap, QPainter, QPen
import pyqtgraph as pg
from fritzconnection.lib.fritzstatus import FritzStatus

# ---------------- Einstellungen ----------------
UPDATE_INTERVAL_MS   = 5000
MAX_HISTORY_POINTS   = 1440
AUTO_SHOW            = True          # jetzt wieder direkt anzeigen (oder False für nur Tray)
ALWAYS_ON_TOP_START  = False         # Startzustand für "Immer im Vordergrund"
FORCE_XCB            = False         # Bei Bedarf True
USE_X11_SKIP_TASKBAR = True          # X11-Properties setzen (xcb)
APP_ORG  = "dezihh"
APP_NAME = "FB-Traffic-KDE"
# ------------------------------------------------

GREEN_UP = '#55ff55'
LIGHT_BLUE_DOWN = '#66CCFF'
DARK_GREY = '#555555'
BORDER_COLOR = '#9a9a9a'

def build_tray_icon():
    pm = QPixmap(16,16)
    pm.fill(Qt.transparent)
    p = QPainter(pm); p.setRenderHint(QPainter.Antialiasing)
    p.setPen(QPen(QColor(GREEN_UP), 2))
    p.drawLine(3,13,8,4); p.drawLine(8,4,13,13)
    p.setPen(QPen(QColor(LIGHT_BLUE_DOWN), 2))
    p.drawLine(3,3,8,12); p.drawLine(8,12,13,3)
    p.end()
    return QIcon(pm)

class HoverPlotWidget(pg.PlotWidget):
    HOVER_DELAY_MS = 2000
    GRID_DIVS = 6
    def __init__(self):
        pg.setConfigOption('foreground','w')
        super().__init__()
        self.setBackground(DARK_GREY)
        self._grid_v=[]; self._grid_h=[]
        self.GRID_PEN = pg.mkPen(color=(200,200,200,150), width=1)
        self.plotItem.hideAxis('left'); self.plotItem.hideAxis('bottom')
        self._hover_active=False
        cross_pen = pg.mkPen('#FFFFFF66', width=1)
        self.vLine = pg.InfiniteLine(angle=90,movable=False,pen=cross_pen)
        self.hLine = pg.InfiniteLine(angle=0,movable=False,pen=cross_pen)
        self.addItem(self.vLine, ignoreBounds=True); self.addItem(self.hLine, ignoreBounds=True)
        self.vLine.hide(); self.hLine.hide()
        self.info_text = pg.TextItem("", anchor=(0,1), color='w')
        self.addItem(self.info_text); self.info_text.hide()
        self.plotItem.vb.sigRangeChanged.connect(self._update_grid)
        self.proxy = pg.SignalProxy(self.scene().sigMouseMoved, rateLimit=60, slot=self._on_mouse_moved)
        self.setMouseTracking(True)
        self._hover_timer = QTimer(self); self._hover_timer.setSingleShot(True)
        self._hover_timer.timeout.connect(self._activate_hover)
        QTimer.singleShot(60, self._update_grid)

    def _clear_grid(self):
        for ln in self._grid_v + self._grid_h:
            try: self.removeItem(ln)
            except: pass
        self._grid_v.clear(); self._grid_h.clear()

    def _update_grid(self):
        (x_min,x_max),(y_min,y_max)=self.plotItem.vb.viewRange()
        if x_max<=x_min or y_max<=y_min: return
        self._clear_grid()
        for i in range(self.GRID_DIVS+1):
            xv = x_min + (x_max - x_min)*i/self.GRID_DIVS
            ln = pg.InfiniteLine(angle=90,movable=False,pen=self.GRID_PEN); ln.setPos(xv)
            self.addItem(ln, ignoreBounds=True); self._grid_v.append(ln)
        for j in range(self.GRID_DIVS+1):
            yv = y_min + (y_max - y_min)*j/self.GRID_DIVS
            ln = pg.InfiniteLine(angle=0,movable=False,pen=self.GRID_PEN); ln.setPos(yv)
            self.addItem(ln, ignoreBounds=True); self._grid_h.append(ln)

    def _activate_hover(self):
        self._hover_active=True
        self.plotItem.showAxis('left'); self.plotItem.showAxis('bottom')
        for a in ('left','bottom'):
            ax = self.plotItem.getAxis(a)
            ax.setStyle(showValues=True, tickLength=5)
            ax.setPen(pg.mkPen('#DDDDDD'))
        self.vLine.show(); self.hLine.show(); self.info_text.show()

    def _deactivate_hover(self):
        if self._hover_timer.isActive(): self._hover_timer.stop()
        self._hover_active=False
        self.plotItem.hideAxis('left'); self.plotItem.hideAxis('bottom')
        self.vLine.hide(); self.hLine.hide(); self.info_text.hide()

    def enterEvent(self,e):
        if not self._hover_timer.isActive():
            self._hover_timer.start(self.HOVER_DELAY_MS)
        super().enterEvent(e)

    def leaveEvent(self,e):
        if self._hover_timer.isActive(): self._hover_timer.stop()
        if self._hover_active: self._deactivate_hover()
        super().leaveEvent(e)

    def _on_mouse_moved(self, evt):
        if not self._hover_active: return
        pos = evt[0]
        if not self.plotItem.sceneBoundingRect().contains(pos): return
        mp = self.plotItem.vb.mapSceneToView(pos)
        x,y = mp.x(), mp.y()
        self.vLine.setPos(x); self.hLine.setPos(y)
        vr = self.plotItem.viewRange()
        self.info_text.setPos(vr[0][0], vr[1][1])
        self.info_text.setText(f"x={x:.0f}  y={y:.2f}")

class TrafficMonitor(QWidget):
    RESIZE_HANDLE_SIZE = 18
    def __init__(self, fritzbox):
        super().__init__()
        self.fritzbox=fritzbox
        self.upload_history=deque(maxlen=MAX_HISTORY_POINTS)
        self.download_history=deque(maxlen=MAX_HISTORY_POINTS)
        self.x_values=[]; self.counter=0
        self.last_up=0.0; self.last_down=0.0
        self.settings = QSettings(APP_ORG, APP_NAME)
        self._restoring=True; self._target_pos=None
        self._tray=None
        self._resizing=False
        self._resize_origin=QPoint()
        self._start_geom=QRect()
        self._offset=QPoint()
        self._always_on_top = ALWAYS_ON_TOP_START

        self.initUI()
        self._restore_state()
        self._setup_tray()

        for d in (20,80,160):
            QTimer.singleShot(d,self._apply_target_pos)
        QTimer.singleShot(300,self._finish_restore)

    def _compose_flags(self):
        flags = Qt.FramelessWindowHint | Qt.Tool
        if self._always_on_top:
            flags |= Qt.WindowStaysOnTopHint
        return flags

    def initUI(self):
        self.setWindowFlags(self._compose_flags())
        self.setStyleSheet(f"background:{DARK_GREY}; border:none;")
        layout = QVBoxLayout(self); layout.setContentsMargins(0,0,0,0); layout.setSpacing(0)

        self.title_frame = QWidget(self); self.title_frame.setFixedHeight(50)
        self.title_frame.setStyleSheet(
            f"background:{DARK_GREY};"
            f"border-top:3px solid {BORDER_COLOR};"
            f"border-left:3px solid {BORDER_COLOR};"
            f"border-right:3px solid {BORDER_COLOR};"
        )
        self.title_label = QLabel(self.title_frame); self.title_label.setAlignment(Qt.AlignCenter)
        fl = QVBoxLayout(self.title_frame); fl.setContentsMargins(0,0,0,0); fl.addWidget(self.title_label)
        layout.addWidget(self.title_frame)

        self.plot_widget = HoverPlotWidget()
        self.plot_widget.setStyleSheet(
            f"border-bottom:3px solid {BORDER_COLOR};"
            f"border-left:3px solid {BORDER_COLOR};"
            f"border-right:3px solid {BORDER_COLOR};"
        )
        layout.addWidget(self.plot_widget)

        self.plot_item=self.plot_widget.plotItem
        self.upload_curve = self.plot_widget.plot(pen=pg.mkPen(GREEN_UP,width=2))
        self.download_curve = self.plot_widget.plot(pen=pg.mkPen(LIGHT_BLUE_DOWN,width=2))

        self.timer = QTimer(self); self.timer.timeout.connect(self.update_traffic); self.timer.start(UPDATE_INTERVAL_MS)

        if not self.settings.contains('geometry'):
            self.resize(620,320)
        self._update_title(0.0,0.0)

    # ---- X11 Skip Taskbar (vor show) ----
    def apply_x11_skip_taskbar(self):
        if not USE_X11_SKIP_TASKBAR: return
        if QApplication.platformName().lower() != "xcb": return
        try:
            from Xlib import display, X
            wid = int(self.winId())
            d = display.Display()
            w = d.create_resource_object('window', wid)
            atom_state = d.intern_atom('_NET_WM_STATE')
            atom_skip_task = d.intern_atom('_NET_WM_STATE_SKIP_TASKBAR')
            atom_skip_pager = d.intern_atom('_NET_WM_STATE_SKIP_PAGER')
            w.change_property(atom_state, X.Atom.ATOM, 32,
                              [atom_skip_task, atom_skip_pager],
                              X.PropModeReplace)
            atom_type = d.intern_atom('_NET_WM_WINDOW_TYPE')
            atom_utility = d.intern_atom('_NET_WM_WINDOW_TYPE_UTILITY')
            w.change_property(atom_type, X.Atom.ATOM, 32, [atom_utility], X.PropModeReplace)
            d.sync()
        except Exception:
            pass

    # ---- Zustandsverwaltung ----
    def _restore_state(self):
        geo = self.settings.value('geometry')
        if isinstance(geo,QByteArray):
            self.restoreGeometry(geo)
        elif geo:
            try: self.restoreGeometry(QByteArray(str(geo).encode('latin1')))
            except: pass
        pos = self.settings.value('pos')
        if isinstance(pos,QPoint):
            self._target_pos=pos
        elif pos:
            try:
                x,y = map(int,str(pos).split(','))
                self._target_pos=QPoint(x,y)
            except: pass

    def _apply_target_pos(self):
        if self._target_pos and self._restoring:
            self.move(self._target_pos)

    def _finish_restore(self):
        self._restoring=False

    def _save_state(self):
        if self._restoring: return
        self.settings.setValue('geometry', self.saveGeometry())
        self.settings.setValue('pos', self.pos())

    # ---- Maus / Drag / Resize ----
    def mousePressEvent(self, ev):
        if ev.button()==Qt.LeftButton:
            if self.title_frame.geometry().contains(ev.pos()):
                w=self.windowHandle()
                if w:
                    try: w.startSystemMove(); return
                    except: pass
                self._offset = ev.globalPos()-self.frameGeometry().topLeft()
                ev.accept(); return
            if self._in_resize_corner(ev.pos()):
                w=self.windowHandle()
                if w:
                    try: w.startSystemResize(Qt.BottomRightCorner); return
                    except: pass
                self._resizing=True
                self._resize_origin=ev.globalPos()
                self._start_geom=self.geometry()
                ev.accept(); return
        super().mousePressEvent(ev)

    def mouseMoveEvent(self, ev):
        if not self._resizing and (ev.buttons() & Qt.LeftButton) and not self._offset.isNull():
            self.move(ev.globalPos()-self._offset)
            ev.accept(); return
        if self._resizing:
            diff = ev.globalPos()-self._resize_origin
            new_w = max(200, self._start_geom.width()+diff.x())
            new_h = max(100, self._start_geom.height()+diff.y())
            self.setGeometry(QRect(self._start_geom.topLeft(),
                                   QPoint(self._start_geom.left()+new_w,
                                          self._start_geom.top()+new_h)))
            ev.accept(); return
        if self._in_resize_corner(ev.pos()):
            self.setCursor(Qt.SizeFDiagCursor)
        else:
            if self.cursor().shape()==Qt.SizeFDiagCursor:
                self.unsetCursor()

    def mouseReleaseEvent(self, ev):
        if ev.button()==Qt.LeftButton and self._resizing:
            self._resizing=False
        if ev.button()==Qt.LeftButton:
            self._save_state()
        self._offset=QPoint()
        super().mouseReleaseEvent(ev)

    # ---- Events ----
    def moveEvent(self, ev):
        super().moveEvent(ev)
        if self.isVisible() and not self._restoring:
            self._save_state()

    def resizeEvent(self, ev):
        super().resizeEvent(ev)
        self._update_title(self.last_up,self.last_down)
        if self.isVisible() and not self._restoring:
            self._save_state()

    def closeEvent(self, ev):
        self._save_state()
        if self.timer.isActive(): self.timer.stop()
        if self._tray: self._tray.hide()
        super().closeEvent(ev)

    # ---- Helpers ----
    def _calc_font_size(self, up, down):
        max_w=self.width()
        test="Down: 9999.99 kB/s"
        for fs in range(16,9,-1):
            if len(test)*fs*0.48 <= max_w-10: return fs
        return 10

    def _update_title(self, up, down):
        fs=self._calc_font_size(up,down)
        self.title_label.setStyleSheet(f"font-weight:bold; font-size:{fs}px; padding-top:5px;")
        self.title_label.setText(
            f"<span style='color:{GREEN_UP};'>Up: {up:.2f} kB/s</span>"
            f"<br><span style='color:{LIGHT_BLUE_DOWN};'>Down: {down:.2f} kB/s</span>"
        )

    def _in_resize_corner(self,pos):
        return (self.width()-pos.x() <= self.RESIZE_HANDLE_SIZE) and (self.height()-pos.y() <= self.RESIZE_HANDLE_SIZE)

    # ---- Tray ----
    def _setup_tray(self):
        QApplication.instance().setQuitOnLastWindowClosed(False)
        if not QSystemTrayIcon.isSystemTrayAvailable(): return
        self._tray = QSystemTrayIcon(build_tray_icon(), self)
        menu = QMenu()
        self.act_toggle = QAction("Anzeigen / Verstecken", self)
        self.act_refresh = QAction("Jetzt aktualisieren", self)
        self.act_top = QAction("Immer im Vordergrund", self); self.act_top.setCheckable(True); self.act_top.setChecked(self._always_on_top)
        self.act_quit = QAction("Beenden", self)
        self.act_toggle.triggered.connect(self._toggle_visible)
        self.act_refresh.triggered.connect(self.update_traffic)
        self.act_top.triggered.connect(self._toggle_on_top)
        self.act_quit.triggered.connect(self._quit)
        menu.addAction(self.act_toggle); menu.addAction(self.act_refresh); menu.addAction(self.act_top); menu.addSeparator(); menu.addAction(self.act_quit)
        self._tray.setContextMenu(menu)
        self._tray.activated.connect(self._tray_activated)
        self._tray.show()

    def _toggle_on_top(self):
        self._always_on_top = self.act_top.isChecked()
        vis = self.isVisible()
        self.hide()
        self.setWindowFlags(self._compose_flags())
        self.apply_x11_skip_taskbar()
        if vis:
            self.show()

    def _tray_activated(self, reason):
        if reason == QSystemTrayIcon.Trigger:
            self._toggle_visible()

    def _toggle_visible(self):
        if self.isVisible(): self.hide()
        else:
            # Normales Tool-Fenster (kein Popup) -> verschiebbar, kein erzwungenes on-top
            vis = self.isVisible()
            self.hide()
            self.setWindowFlags(self._compose_flags())
            self.apply_x11_skip_taskbar()
            self.show()
            if not vis and self._target_pos:  # falls erster Show nach Start
                self.move(self._target_pos)

    def _quit(self):
        self.close()
        QApplication.instance().quit()

    # ---- Daten ----
    def update_traffic(self):
        try:
            rates = self.fritzbox.transmission_rate
        except Exception as e:
            self.title_label.setText(
                f"<span style='color:{GREEN_UP};'>Fehler:</span><br><span style='color:{LIGHT_BLUE_DOWN};'>{e}</span>"
            )
            return
        up = rates[0]/1024.0; down = rates[1]/1024.0
        self.last_up=up; self.last_down=down
        self._update_title(up,down)
        self.upload_history.append(up); self.download_history.append(down)
        self.counter += 1
        self.x_values = list(range(self.counter - len(self.upload_history) + 1, self.counter + 1))
        self.upload_curve.setData(self.x_values, list(self.upload_history))
        self.download_curve.setData(self.x_values, list(self.download_history))
        self.plot_widget.plotItem.enableAutoRange(axis=pg.ViewBox.XYAxes, enable=True)

#def load_config(path='config.ini'):
    #config=configparser.ConfigParser()
    #if not config.read(path):
        #raise FileNotFoundError(f"Konfigurationsdatei {path} nicht gefunden")
    #address=config.get('credentials','address',fallback='fritz.box')
    #password=config.get('credentials','password',fallback='')
    #return address,password

def load_config(filename='config.ini'):
    import os, configparser
    script_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(script_dir, filename)
    config = configparser.ConfigParser()
    if not config.read(path):
        raise FileNotFoundError(f"Konfigurationsdatei {path} nicht gefunden")
    address = config.get('credentials', 'address', fallback='fritz.box')
    password = config.get('credentials', 'password', fallback='')
    return address, password

if __name__ == "__main__":
    try:
        if FORCE_XCB and os.environ.get("QT_QPA_PLATFORM","")!="xcb":
            os.environ["QT_QPA_PLATFORM"]="xcb"
        address,password = load_config()
        fritzbox = FritzStatus(address=address, password=password)
        app = QApplication(sys.argv)
        app.setApplicationName(APP_NAME)
        app.setOrganizationName(APP_ORG)
        signal.signal(signal.SIGINT, lambda *a: app.quit())
        monitor = TrafficMonitor(fritzbox)
        monitor.apply_x11_skip_taskbar()
        if AUTO_SHOW:
            monitor.show()
        sys.exit(app.exec_())
    except Exception as e:
        print(f"Error: {e}")
