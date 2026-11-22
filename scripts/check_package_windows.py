"""Validate a relocated Windows GUI executable."""
import ctypes
from ctypes import wintypes
import struct

from package_common import version
from windows_gui import MANIFEST, version_resource


def check_architecture(data):
    assert data[:2] == b'MZ'
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[pe:pe + 4] == b'PE\0\0'
    assert struct.unpack_from('<H', data, pe + 4)[0] == 0x8664, 'Not Windows x64'
    assert struct.unpack_from('<H', data, pe + 24 + 68)[0] == 2, 'Not a GUI executable'


def check_payload(binary):
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    api.LoadLibraryExW.restype = wintypes.HMODULE
    api.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    api.FindResourceW.restype = ctypes.c_void_p
    api.FreeLibrary.argtypes = [wintypes.HMODULE]
    module = api.LoadLibraryExW(str(binary), None, 2)
    assert module, 'Could not load executable resources'
    try:
        api.SizeofResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
        api.SizeofResource.restype = wintypes.DWORD
        api.LoadResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
        api.LoadResource.restype = wintypes.HGLOBAL
        api.LockResource.argtypes = [wintypes.HGLOBAL]
        api.LockResource.restype = ctypes.c_void_p
        expected = {16: version_resource(version()), 24: MANIFEST}
        for kind in (14, 16, 24):
            resource = api.FindResourceW(module, 1, kind)
            assert resource, f'Missing PE resource type {kind}'
            if kind in expected:
                loaded = api.LoadResource(module, resource)
                address = api.LockResource(loaded)
                assert address, f'Cannot read PE resource type {kind}'
                payload = ctypes.string_at(address, api.SizeofResource(module, resource))
                assert payload == expected[kind], f'Incorrect PE resource type {kind}'
    finally:
        api.FreeLibrary(module)
    # Reject DLLs copied from a developer machine: only OS DLL imports are allowed.
    data = binary.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    sections = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    table = pe + 24 + optional_size

    def offset(rva):
        for i in range(sections):
            size, address, raw_size, raw = struct.unpack_from('<IIII', data, table + i * 40 + 8)
            if address <= rva < address + max(size, raw_size):
                return raw + rva - address
        raise ValueError(f'Unmapped RVA {rva}')

    # PE32+ import table (directory index 1).
    imports = struct.unpack_from('<I', data, pe + 24 + 112 + 8)[0]
    if imports:
        cursor = offset(imports)
        system = {'kernel32.dll', 'user32.dll', 'gdi32.dll', 'advapi32.dll', 'shell32.dll',
                  'ole32.dll', 'oleaut32.dll', 'imm32.dll', 'version.dll', 'winmm.dll',
                  'setupapi.dll', 'cfgmgr32.dll', 'hid.dll', 'ws2_32.dll', 'ntdll.dll',
                  'ucrtbase.dll', 'msvcrt.dll', 'comdlg32.dll', 'comctl32.dll', 'shlwapi.dll',
                  'dwmapi.dll', 'dxgi.dll', 'd3d11.dll', 'd3d12.dll', 'dxguid.dll',
                  'bcrypt.dll', 'crypt32.dll', 'winhttp.dll', 'rpcrt4.dll', 'propsys.dll',
                  'avrt.dll', 'powrprof.dll', 'wintrust.dll', 'shcore.dll', 'dbghelp.dll',
                  'winspool.drv', 'dinput8.dll', 'dsound.dll', 'iphlpapi.dll', 'userenv.dll',
                  'secur32.dll', 'psapi.dll', 'opengl32.dll', 'glu32.dll', 'd3dcompiler_47.dll'}
        while any(data[cursor:cursor + 20]):
            name_rva = struct.unpack_from('<I', data, cursor + 12)[0]
            start = offset(name_rva)
            name = data[start:data.index(0, start)].decode('ascii').lower()
            assert name in system or name.startswith(('api-ms-win-', 'ext-ms-win-')), f'Non-system DLL dependency: {name}'
            cursor += 20
    return binary
