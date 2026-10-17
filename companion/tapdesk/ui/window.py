"""The companion's window and tray icon.

Follows `docs/design-system.md` section 7, including the one deliberate
exception: the window is dark but the QR code inside it is black on white,
because scanners need real contrast.

The window is the whole security story made visible. A user should be able to
see, without reading anything, which computer it is talking to, that a phone is
waiting for permission, and that they can revoke any device already paired.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Callable

from PySide6.QtCore import Qt, QTimer, Signal
from PySide6.QtGui import QAction, QColor, QIcon, QImage, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QFrame,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)

from .. import qr as qr_render
from ..devices import Device
from ..session import Session

log = logging.getLogger("tapdesk.ui")

# Tokens from the design system.
BACKGROUND = QColor("#0A0A0A")
SURFACE = QColor("#171717")
SURFACE_ELEVATED = QColor("#1F1F1F")
PRIMARY = QColor("#16A34A")
PRIMARY_PRESSED = QColor("#15803D")
HIGHLIGHT = QColor("#86EFAC")
TEXT = QColor("#FAFAFA")
TEXT_MUTED = QColor("#9CA3AF")
ERROR = QColor("#DC2626")
WARNING = QColor("#F59E0B")
DIVIDER = QColor("#262626")


def dot_icon(colour: QColor, size: int = 16) -> QIcon:
    """A small filled circle, for the tray and the status row."""
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setBrush(colour)
    painter.setPen(Qt.PenStyle.NoPen)
    painter.drawEllipse(0, 0, size - 1, size - 1)
    painter.end()
    return QIcon(pixmap)


@dataclass
class UiCallbacks:
    """What the window needs the application to do for it."""

    on_disconnect: Callable[[], None]
    on_revoke: Callable[[str], None]
    on_quit: Callable[[], None]


class MainWindow(QWidget):
    """The QR window."""

    countdown = Signal()

    def __init__(self, callbacks: UiCallbacks) -> None:
        super().__init__()
        self._callbacks = callbacks
        self._session: Session | None = None
        self._pin_visible = False
        # Which deep link is currently drawn. Initialised here because the
        # first set_session() compares against it, and reading it before it
        # exists crashed the app on its very first frame.
        self._last_link: str | None = None
        self._build()

    # -- construction ------------------------------------------------------

    def _build(self) -> None:
        self.setWindowTitle("TapDesk")
        self.setFixedWidth(400)
        self.setStyleSheet(_STYLESHEET)

        root = QVBoxLayout(self)
        root.setContentsMargins(24, 20, 24, 20)
        root.setSpacing(14)

        root.addWidget(self._header())
        root.addWidget(self._status_row(), alignment=Qt.AlignmentFlag.AlignLeft)
        root.addWidget(self._qr_frame(), alignment=Qt.AlignmentFlag.AlignHCenter)
        root.addWidget(self._details())
        root.addWidget(self._devices_section())
        root.addStretch(1)
        root.addWidget(self._footer())

        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self._tick)
        self._timer.start()

    def _header(self) -> QWidget:
        holder = QWidget()
        layout = QHBoxLayout(holder)
        layout.setContentsMargins(0, 0, 0, 0)

        self._title = QLabel("TapDesk")
        self._title.setObjectName("title")

        self._quit = QPushButton("Quit")
        self._quit.setObjectName("quiet")
        self._quit.clicked.connect(self._callbacks.on_quit)

        layout.addWidget(self._title)
        layout.addStretch(1)
        layout.addWidget(self._quit)
        return holder

    def _status_row(self) -> QWidget:
        holder = QWidget()
        layout = QHBoxLayout(holder)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        self._status_dot = QLabel()
        self._status_dot.setFixedSize(12, 12)
        self._status_text = QLabel("Not connected")
        self._status_text.setObjectName("muted")

        layout.addWidget(self._status_dot)
        layout.addWidget(self._status_text)
        layout.addStretch(1)
        return holder

    def _qr_frame(self) -> QWidget:
        self._qr_frame_widget = QFrame()
        self._qr_frame_widget.setObjectName("qrFrame")
        layout = QVBoxLayout(self._qr_frame_widget)
        layout.setContentsMargins(14, 14, 14, 14)

        self._qr_label = QLabel()
        self._qr_label.setFixedSize(260, 260)
        self._qr_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self._qr_label, alignment=Qt.AlignmentFlag.AlignHCenter)
        return self._qr_frame_widget

    def _details(self) -> QWidget:
        holder = QWidget()
        layout = QVBoxLayout(holder)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        self._name = QLabel("This computer")
        self._name.setObjectName("heading")
        self._name.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self._address = QLabel("")
        self._address.setObjectName("mono")
        self._address.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # The PIN and fingerprint are shown only when the manual fallback is
        # actually needed. Putting a one-time code on screen permanently would
        # invite shoulder-surfing for no benefit.
        self._manual = QLabel("")
        self._manual.setObjectName("pin")
        self._manual.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._manual.setVisible(False)

        self._fingerprint = QLabel("")
        self._fingerprint.setObjectName("fingerprint")
        self._fingerprint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._fingerprint.setWordWrap(True)

        layout.addWidget(self._name)
        layout.addWidget(self._address)
        layout.addWidget(self._manual)
        layout.addWidget(self._fingerprint)
        return holder

    def _devices_section(self) -> QWidget:
        self._devices_holder = QWidget()
        layout = QVBoxLayout(self._devices_holder)
        layout.setContentsMargins(0, 10, 0, 0)
        layout.setSpacing(6)

        heading = QLabel("PAIRED DEVICES")
        heading.setObjectName("muted")
        layout.addWidget(heading)

        self._devices = QListWidget()
        self._devices.setObjectName("devices")
        self._devices.setMaximumHeight(110)
        self._devices.itemDoubleClicked.connect(self._revoke_selected)
        layout.addWidget(self._devices)

        hint = QLabel("Double-click a device to revoke it.")
        hint.setObjectName("fingerprint")
        layout.addWidget(hint)
        return self._devices_holder

    def _footer(self) -> QWidget:
        holder = QWidget()
        layout = QHBoxLayout(holder)
        layout.setContentsMargins(0, 6, 0, 0)

        self._disconnect = QPushButton("Disconnect")
        self._disconnect.setObjectName("primary")
        self._disconnect.setEnabled(False)
        self._disconnect.clicked.connect(self._callbacks.on_disconnect)

        layout.addWidget(self._disconnect)
        return holder

    # -- updates -----------------------------------------------------------

    def set_session(self, session: Session) -> None:
        """Show a session, redrawing the QR when the deep link changes."""
        self._session = session
        deep_link = session.deep_link()
        if self._qr_label.pixmap() is None or self._last_link != deep_link:
            self._last_link = deep_link
            image = QImage.fromData(qr_render.render(deep_link).png)
            self._qr_label.setPixmap(
                QPixmap.fromImage(image).scaled(
                    260, 260,
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
            )

        self._name.setText(session.name)
        hosts = ", ".join(session.ips) if session.ips else "no network address"
        self._address.setText(f"{hosts}  ·  port {session.port}")

        fingerprint = session.fingerprint
        self._fingerprint.setText(f"certificate {fingerprint[:16]}…")

        if self._pin_visible:
            # The PIN is the six-digit rendering of the token, for typing when
            # the camera will not work.
            digits = "".join(
                str((ord(c) % 10)) for c in session.token.value[:6]
            )
            self._manual.setText(f"PIN  {digits}")
            self._manual.setVisible(True)
        else:
            self._manual.setVisible(False)

    def show_pin(self, visible: bool) -> None:
        self._pin_visible = visible
        if self._session is not None:
            self.set_session(self._session)

    def set_status(self, text: str, colour: QColor) -> None:
        self._status_text.setText(text)
        self._status_text.setStyleSheet(f"color: {colour.name()};")
        self._status_dot.setPixmap(dot_icon(colour, 12).pixmap(12, 12))

    def set_connected(self, connected: bool, count: int = 0) -> None:
        self._disconnect.setEnabled(connected)
        if connected:
            plural = "phone" if count == 1 else "phones"
            self.set_status(f"{count} {plural} connected", PRIMARY)
        else:
            self.set_status("Ready to pair", TEXT_MUTED)

    def set_devices(self, devices: list[Device]) -> None:
        self._devices.clear()
        for device in devices:
            item = QListWidgetItem(device.name)
            item.setData(Qt.ItemDataRole.UserRole, device.device_id)
            item.setToolTip("Double-click to revoke")
            self._devices.addItem(item)
        self._devices_holder.setVisible(bool(devices))

    def _revoke_selected(self, item: QListWidgetItem) -> None:
        device_id = item.data(Qt.ItemDataRole.UserRole)
        if device_id:
            self._callbacks.on_revoke(str(device_id))

    def _tick(self) -> None:
        if self._session is None:
            return
        # Refreshing the QR as the token runs out is not cosmetic: a code left
        # on screen for ten minutes is a code that has already expired, and the
        # user who scans it gets a failure they cannot explain.
        if self._session.seconds_remaining <= 0 or self._session.token.consumed:
            self.countdown.emit()

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt naming
        event.ignore()
        self.hide()


class Tray(QSystemTrayIcon):
    """The system tray presence, so the companion is never invisible."""

    def __init__(self, callbacks: UiCallbacks) -> None:
        super().__init__(dot_icon(TEXT_MUTED))
        self._callbacks = callbacks
        self.setToolTip("TapDesk")

        menu = self.contextMenu()
        if menu is None:
            from PySide6.QtWidgets import QMenu

            menu = QMenu()

        show = QAction("Show QR code", menu)
        show.triggered.connect(callbacks.on_disconnect if False else self._noop)
        show.triggered.connect(self._show_requested)
        menu.addAction(show)

        disconnect = QAction("Disconnect all", menu)
        disconnect.triggered.connect(callbacks.on_disconnect)
        menu.addAction(disconnect)
        menu.addSeparator()

        quit_action = QAction("Quit TapDesk", menu)
        quit_action.triggered.connect(callbacks.on_quit)
        menu.addAction(quit_action)

        self.setContextMenu(menu)
        self._show_requested = lambda: None

    def _show_requested(self) -> None:  # pragma: no cover - overridden by app
        pass

    def _noop(self) -> None:
        pass

    def set_connected(self, connected: bool) -> None:
        self.setIcon(dot_icon(PRIMARY if connected else TEXT_MUTED))
        self.setToolTip("TapDesk - connected" if connected else "TapDesk")


_STYLESHEET = f"""
QWidget {{
    background: {BACKGROUND.name()};
    color: {TEXT.name()};
    font-family: "Inter", "Segoe UI", sans-serif;
}}
QLabel#title {{ font-size: 19px; font-weight: 600; }}
QLabel#heading {{ font-size: 17px; font-weight: 600; }}
QLabel#muted {{ color: {TEXT_MUTED.name()}; font-size: 12px; }}
QLabel#mono {{ color: {TEXT_MUTED.name()}; font-size: 13px; font-family: "JetBrains Mono", "Consolas", monospace; }}
QLabel#pin {{ color: {HIGHLIGHT.name()}; font-size: 20px; font-weight: 700; font-family: "JetBrains Mono", "Consolas", monospace; }}
QLabel#fingerprint {{ color: {DIVIDER.name()}; font-size: 10px; font-family: "JetBrains Mono", "Consolas", monospace; }}
QFrame#qrFrame {{
    background: white;
    border-radius: 12px;
}}
QListWidget {{
    background: {SURFACE.name()};
    border: 1px solid {DIVIDER.name()};
    border-radius: 8px;
    color: {TEXT.name()};
    font-size: 13px;
}}
QPushButton#primary {{
    background: {PRIMARY.name()};
    color: white;
    border: none;
    border-radius: 18px;
    padding: 12px 22px;
    font-size: 14px;
    font-weight: 600;
}}
QPushButton#primary:hover {{ background: {PRIMARY_PRESSED.name()}; }}
QPushButton#primary:disabled {{
    background: {SURFACE_ELEVATED.name()};
    color: {DIVIDER.name()};
}}
QPushButton#quiet {{
    background: transparent;
    border: 1px solid {DIVIDER.name()};
    border-radius: 14px;
    color: {TEXT_MUTED.name()};
    padding: 6px 14px;
    font-size: 12px;
}}
QPushButton#quiet:hover {{ color: {TEXT.name()}; }}
"""
