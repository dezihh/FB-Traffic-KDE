# contents/python/TrafficProvider.py

from PyQt5.QtCore import QObject, pyqtProperty, QTimer
import random

class TrafficProvider(QObject):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._upload = "0.00 kB/s"
        self._download = "0.00 kB/s"

        # Timer für Simulation
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._update)
        self.timer.start(1000)

    def _update(self):
        up = round(random.uniform(0.1, 3.5), 2)
        down = round(random.uniform(0.5, 12.0), 2)
        self._upload = f"{up:.2f} kB/s"
        self._download = f"{down:.2f} kB/s"

    @pyqtProperty(str, constant=False)
    def upload(self):
        return self._upload

    @pyqtProperty(str, constant=False)
    def download(self):
        return self._download
