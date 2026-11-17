"""Embed an ICO and select the Windows GUI subsystem in a distribution copy.

The development executable retains its console for the CLI regression suite.
Uses Windows resource APIs, with no downloaded resource editor or PE library.
"""
import ctypes
from ctypes import wintypes
from pathlib import Path
import struct


def prepare(executable: Path, icon: Path):
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    api.BeginUpdateResourceW.restype = wintypes.HANDLE
    api.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
    api.UpdateResourceW.restype = wintypes.BOOL
    api.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    api.EndUpdateResourceW.restype = wintypes.BOOL
    data = icon.read_bytes()
    reserved, kind, count = struct.unpack_from('<HHH', data)
    if reserved != 0 or kind != 1 or not count:
        raise ValueError('Invalid ICO')
    handle = api.BeginUpdateResourceW(str(executable.resolve()), False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    committed = False
    try:
        group = bytearray(struct.pack('<HHH', 0, 1, count))
        for index in range(count):
            entry = struct.unpack_from('<BBBBHHII', data, 6 + index * 16)
            width, height, colors, zero, planes, bits, size, offset = entry
            image = data[offset:offset + size]
            if len(image) != size:
                raise ValueError('Truncated ICO')
            buffer = ctypes.create_string_buffer(image)
            if not api.UpdateResourceW(handle, 3, index + 1, 0, buffer, size):
                raise ctypes.WinError(ctypes.get_last_error())
            group.extend(struct.pack('<BBBBHHIH', width, height, colors, zero, planes, bits, size, index + 1))
        buffer = ctypes.create_string_buffer(bytes(group))
        if not api.UpdateResourceW(handle, 14, 1, 0, buffer, len(group)):
            raise ctypes.WinError(ctypes.get_last_error())
        committed = True
    finally:
        if not api.EndUpdateResourceW(handle, not committed):
            raise ctypes.WinError(ctypes.get_last_error())
    data = bytearray(executable.read_bytes())
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Invalid PE')
    # IMAGE_OPTIONAL_HEADER: Subsystem at +68, CheckSum at +64 (PE32/PE32+).
    optional = pe + 24
    struct.pack_into('<H', data, optional + 68, 2)  # WINDOWS_GUI
    struct.pack_into('<I', data, optional + 64, 0)
    executable.write_bytes(data)
