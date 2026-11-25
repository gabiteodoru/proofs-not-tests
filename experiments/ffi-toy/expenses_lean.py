"""Toy expense report, with `categorize` replaced by compiled Lean code.

Everything except `categorize` is the unchanged code from `expenses.py`.
`categorize` here is glue only: it marshals arguments to the Lean function
`Toy.categorize` (proven: an accepted category is on the allow-list) through
the C shim in `c/toy_shim.c`. This glue and the shim are trusted, not proven.
"""

from __future__ import annotations

import ctypes
import sys
from pathlib import Path
from typing import Optional, Sequence

import expenses
from expenses import CategoryError

_LIB_PATH = Path(__file__).resolve().parent / "build" / "libtoy.so"
_lib = ctypes.CDLL(str(_LIB_PATH))

_lib.toy_init.restype = ctypes.c_int
_lib.toy_categorize_c.restype = ctypes.c_int
_lib.toy_categorize_c.argtypes = [
    ctypes.c_char_p, ctypes.c_size_t,                    # merchant
    ctypes.c_char_p, ctypes.c_size_t,                    # declared (NULL = None)
    ctypes.POINTER(ctypes.c_char_p),                     # allowed
    ctypes.POINTER(ctypes.c_size_t),                     # allowed lengths
    ctypes.c_size_t,                                     # number allowed
    ctypes.POINTER(ctypes.c_void_p),                     # out
    ctypes.POINTER(ctypes.c_size_t),                     # out length
]
_lib.toy_free.argtypes = [ctypes.c_void_p]
_lib.toy_free.restype = None

if _lib.toy_init() != 0:
    raise RuntimeError("Lean runtime initialization failed")


def _utf8(s: str) -> bytes:
    # A str with lone surrogates can't be encoded as UTF-8, and a Lean String
    # can't contain surrogates. We reject such input (see
    # notes/python-lean-contract-gaps.md).
    try:
        return s.encode("utf-8")
    except UnicodeEncodeError as e:
        raise CategoryError(f"input is not valid Unicode text: {e}") from None


def categorize(merchant: str, declared: Optional[str], allowed: Sequence[str]) -> str:
    m = _utf8(merchant)
    d = None if declared is None else _utf8(declared)
    enc = [_utf8(a) for a in allowed]
    arr = (ctypes.c_char_p * len(enc))(*enc)
    lens = (ctypes.c_size_t * len(enc))(*[len(b) for b in enc])
    out = ctypes.c_void_p()
    out_len = ctypes.c_size_t()
    rc = _lib.toy_categorize_c(
        m, len(m), d, 0 if d is None else len(d),
        arr, lens, len(enc), ctypes.byref(out), ctypes.byref(out_len),
    )
    try:
        text = ctypes.string_at(out.value, out_len.value).decode("utf-8")
    finally:
        _lib.toy_free(out)
    if rc == 0:
        return text
    raise CategoryError(text)


if __name__ == "__main__":
    sys.exit(expenses.main(sys.argv, categorize_fn=categorize))
