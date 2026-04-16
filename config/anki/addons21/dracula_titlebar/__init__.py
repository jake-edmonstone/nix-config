"""Make Anki's title bar blend with the Dracula theme on macOS.

Sets titlebarAppearsTransparent and the window background color to Dracula's
base (#282a36) via ctypes → ObjC runtime, so no PyObjC dependency is needed.
"""

import sys
if sys.platform != "darwin":
    raise RuntimeError("macOS only")

import ctypes
import ctypes.util
from ctypes import c_void_p, c_char_p, c_double, c_bool

from aqt import mw, gui_hooks

# Dracula palette
_BG = (0x28 / 255, 0x2A / 255, 0x36 / 255)  # #282a36

_objc = ctypes.cdll.LoadLibrary(ctypes.util.find_library("objc"))
_objc.objc_getClass.restype = c_void_p
_objc.objc_getClass.argtypes = [c_char_p]
_objc.sel_registerName.restype = c_void_p
_objc.sel_registerName.argtypes = [c_char_p]
_objc.objc_msgSend.restype = c_void_p
_objc.objc_msgSend.argtypes = [c_void_p, c_void_p]

_sel = _objc.sel_registerName
_msg = _objc.objc_msgSend

_msg_bool = ctypes.CFUNCTYPE(None, c_void_p, c_void_p, c_bool)
_set_bool = _msg_bool(("objc_msgSend", _objc))

_msg_ptr = ctypes.CFUNCTYPE(None, c_void_p, c_void_p, c_void_p)
_set_ptr = _msg_ptr(("objc_msgSend", _objc))

_msg_rgba = ctypes.CFUNCTYPE(c_void_p, c_void_p, c_void_p, c_double, c_double, c_double, c_double)
_color_rgba = _msg_rgba(("objc_msgSend", _objc))

NSColor = _objc.objc_getClass(b"NSColor")


def _dracula_color():
    return _color_rgba(
        NSColor,
        _sel(b"colorWithSRGBRed:green:blue:alpha:"),
        *_BG,
        1.0,
    )


def _style_window(ns_window):
    # titlebarAppearsTransparent = YES
    _set_bool(ns_window, _sel(b"setTitlebarAppearsTransparent:"), True)
    # backgroundColor = Dracula base
    _set_ptr(ns_window, _sel(b"setBackgroundColor:"), _dracula_color())


def _style_all_windows():
    app = mw.app
    for widget in app.topLevelWidgets():
        wid = widget.winId()
        if wid:
            ns_view = int(wid)
            ns_window = _msg(c_void_p(ns_view), _sel(b"window"))
            if ns_window:
                _style_window(ns_window)


def _on_main_window_did_init():
    _style_all_windows()


gui_hooks.main_window_did_init.append(_on_main_window_did_init)
