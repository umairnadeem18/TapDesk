# -*- mode: python ; coding: utf-8 -*-
"""Freeze the TapDesk companion into a single executable.

The alternative - shipping the venv - would mean asking a teacher to have
Python installed and to run a command line, which is not a thing we can
reasonably ask of someone installing a classroom tool.

Three decisions here are deliberate.

The certificate is *not* bundled. It is generated on the user's machine at first
run, inside their own profile, and never shipped. Bundling one would mean every
install shared a private key, so anyone with the binary could impersonate every
other user's PC. Generating per machine is the whole point.

`tapdesk.exe` is a console-less windowed build. A console window flashing open
and closed on launch is the first thing that makes an app look cheap.

`pystray` is deliberately absent even though it is a dependency. The tray here is
a real `QSystemTrayIcon`, and bundling pystray as well would mean two tray
backends in one process, fighting over the same icon.
"""

import sys
from pathlib import Path

# PySide6 is large; excluding the modules we never touch keeps the installer
# from ballooning to several hundred megabytes.
EXCLUDES = [
    "PySide6.QtWebEngineCore",
    "PySide6.QtWebEngineWidgets",
    "PySide6.QtWebEngineQuick",
    "PySide6.Qt3DCore",
    "PySide6.QtMultimedia",
    "PySide6.QtQuick3D",
    "PySide6.QtCharts",
    "PySide6.QtDataVisualization",
    "PySide6.QtBluetooth",
    "PySide6.QtNfc",
    "PySide6.QtPositioning",
    "PySide6.QtSerialPort",
    "PySide6.QtSql",
    "PySide6.QtTest",
    "PySide6.QtDesigner",
    "PySide6.QtHelp",
    "tkinter",
    "unittest",
    "pydoc_data",
    "test",
    "lib2to3",
]

block_cipher = None

a = Analysis(
    ["tapdesk/main.py"],
    pathex=[str(Path(SPECPATH))],
    binaries=[],
    datas=[],
    # The GUI has no console, so nothing may try to print. Kept visible so that
    # if it ever does, it shows up on the attached debugger rather than
    # vanishing.
    console=False,
    disable_windowed_traceback=False,
    upx=False,  # UPX trips several antivirus heuristics for no real size win
    exclude_modules=EXCLUDES,
    hookspath=[],
    runtime_hooks=[],
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="TapDesk",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    # windowed: no console window behind the QR code window.
    console=False,
    # A teacher will double-click this. Without an icon it is a mystery file.
    icon=None,
    version="tapdesk/version_info.txt",
)