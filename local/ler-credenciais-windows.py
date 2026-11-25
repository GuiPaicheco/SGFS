"""Read only the SGFS startup credentials protected by Windows DPAPI."""
import ctypes
import json
from ctypes import wintypes
from pathlib import Path
from sys import argv


class Blob(ctypes.Structure):
    _fields_ = [("size", wintypes.DWORD), ("data", ctypes.POINTER(ctypes.c_ubyte))]


def unprotect(path):
    protected = bytes.fromhex(path.read_text(encoding="utf-8-sig").strip())
    buffer = (ctypes.c_ubyte * len(protected)).from_buffer_copy(protected)
    source = Blob(len(protected), buffer)
    result = Blob()
    crypt = ctypes.WinDLL("crypt32", use_last_error=True).CryptUnprotectData
    crypt.argtypes = (ctypes.POINTER(Blob), wintypes.LPVOID, wintypes.LPVOID,
                      wintypes.LPVOID, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(Blob))
    crypt.restype = wintypes.BOOL
    if not crypt(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(result)):
        raise ctypes.WinError(ctypes.get_last_error())
    release = ctypes.WinDLL("kernel32").LocalFree
    release.argtypes = (wintypes.HLOCAL,)
    release.restype = wintypes.HLOCAL
    try:
        return ctypes.string_at(result.data, result.size).decode("utf-16-le").rstrip("\0")
    finally:
        ctypes.memset(result.data, 0, result.size)
        release(ctypes.cast(result.data, wintypes.HLOCAL))


def main():
    root = Path(argv[1])
    print(json.dumps({name: unprotect(root / (name + ".dpapi")) for name in ("jwt", "auth", "rest")}))


if __name__ == "__main__":
    main()
