#!/usr/bin/env python3.12

import importlib
import sys

def check_module(name, attr_version="__version__"):
    try:
        mod = importlib.import_module(name)
        print(f"[OK] {name}")
        print(f"   path: {getattr(mod, '__file__', 'None')}")
        if hasattr(mod, attr_version):
            print(f"   version: {getattr(mod, attr_version)}")
        ok = True
    except ImportError as e:
        print(f"[MISSING] {name} - {e}")
        ok = False
    except Exception as e:
        print(f"[ERROR] {name} - {e}")
        ok = False
    print("-" * 60)
    return ok


def main():
    modules = [
        "numpy",
        "ics.cobraOps",
        "pfs.utils",
        "ics.cobraCharmer",
        "pfs.datamodel",
        "ets_fiber_assigner",
        "opdb",
    ]

    failures = [name for name in modules if not check_module(name)]

    if failures:
        print(f"FAILED imports: {', '.join(failures)}")
        return 1

    print("All required modules imported successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
