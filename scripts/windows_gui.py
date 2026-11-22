"""Embed an ICO and select the Windows GUI subsystem in a distribution copy.

The development executable retains its console for the CLI regression suite.
Uses Windows resource APIs, with no downloaded resource editor or PE library.
"""
import ctypes
from ctypes import wintypes
from pathlib import Path
import struct
import tempfile

from package_common import ROOT, RELEASES, archive, copy_file, documents


def resource_block(key, value=b'', children=(), kind=0, value_length=None):
    """Encode a DWORD-aligned VERSIONINFO node."""
    data = bytearray(struct.pack('<HHH', 0, len(value) if value_length is None else value_length, kind))
    data.extend((key + '\0').encode('utf-16le'))
    data.extend(b'\0' * (-len(data) % 4))
    data.extend(value)
    for child in children:
        data.extend(b'\0' * (-len(data) % 4))
        data.extend(child)
    struct.pack_into('<H', data, 0, len(data))
    return bytes(data)


def version_resource(version):
    major, minor, patch = map(int, version.split('.'))
    if max(major, minor, patch) > 65535:
        raise ValueError('Windows version components must fit in 16 bits')
    high, low = (major << 16) | minor, patch << 16
    fixed = struct.pack('<13I', 0xFEEF04BD, 0x10000, high, low, high, low,
                        0x3f, 0, 0x40004, 1, 0, 0, 0)
    values = dict(CompanyName='bubio', FileDescription='Gooswan WonderSwan emulator',
                  FileVersion=version, InternalName='Gooswan', OriginalFilename='Gooswan.exe',
                  ProductName='Gooswan', ProductVersion=version)
    strings = []
    for key, value in values.items():
        encoded = (value + '\0').encode('utf-16le')
        strings.append(resource_block(key, encoded, kind=1, value_length=len(encoded) // 2))
    table = resource_block('040904b0', children=strings, kind=1)
    translation = resource_block('Translation', struct.pack('<HH', 0x409, 1200))
    return resource_block('VS_VERSION_INFO', fixed, [
        resource_block('StringFileInfo', children=[table], kind=1),
        resource_block('VarFileInfo', children=[translation], kind=1),
    ])


MANIFEST = b'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="1.0.0.0" processorArchitecture="amd64" name="bubio.Gooswan" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges>
    <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
  </requestedPrivileges></security></trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application>
    <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
  </application></compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>
    <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
    <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
  </windowsSettings></application>
</assembly>'''


def resource_languages(api, executable, resources):
    """Preserve language coverage when replacing linker-generated resources."""
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE,
                                      ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD,
                                      ctypes.c_ssize_t)
    api.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    api.LoadLibraryExW.restype = wintypes.HMODULE
    api.FreeLibrary.argtypes = [wintypes.HMODULE]
    api.EnumResourceLanguagesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p,
                                          ctypes.c_void_p, callback_type, ctypes.c_ssize_t]
    api.EnumResourceLanguagesW.restype = wintypes.BOOL
    module = api.LoadLibraryExW(str(executable.resolve()), None, 2)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    languages = {}
    try:
        for kind, identity, _ in resources:
            found = {0}

            @callback_type
            def record(module, kind, name, language, parameter):
                found.add(language)
                return True

            if not api.EnumResourceLanguagesW(module, kind, identity, record, 0):
                error = ctypes.get_last_error()
                if error not in (1812, 1813, 1814, 1815):  # Resource/type/name/language absent.
                    raise ctypes.WinError(error)
            languages[kind, identity] = found
    finally:
        api.FreeLibrary(module)
    return languages


def prepare(executable: Path, icon: Path, version: str):
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
    resources = []
    group = bytearray(struct.pack('<HHH', 0, 1, count))
    for index in range(count):
        entry = struct.unpack_from('<BBBBHHII', data, 6 + index * 16)
        width, height, colors, zero, planes, bits, size, offset = entry
        image = data[offset:offset + size]
        if len(image) != size:
            raise ValueError('Truncated ICO')
        resources.append((3, index + 1, image))
        group.extend(struct.pack('<BBBBHHIH', width, height, colors, zero, planes, bits, size, index + 1))
    resources.extend(((14, 1, bytes(group)), (16, 1, version_resource(version)), (24, 1, MANIFEST)))
    languages = resource_languages(api, executable, resources)
    handle = api.BeginUpdateResourceW(str(executable.resolve()), False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    committed = False
    try:
        for kind, identity, payload in resources:
            buffer = ctypes.create_string_buffer(payload)
            for language in languages[kind, identity]:
                if not api.UpdateResourceW(handle, kind, identity, language, buffer, len(payload)):
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


def package_windows(binary, release, arch):
    output = RELEASES / f'gooswan-{release}-windows-{arch}.zip'
    with tempfile.TemporaryDirectory(prefix='gooswan-package-') as temp:
        stage = Path(temp)
        folder = stage / 'Gooswan'
        documents(folder)
        executable = folder / 'Gooswan.exe'
        copy_file(binary, executable)
        copy_file(binary.with_name('gooswan-link.exe'), folder / 'gooswan-link.exe')
        prepare(executable, ROOT / 'assets/icons/Gooswan.ico', release)
        executable.chmod(0o755)
        return [archive(stage, output)]
