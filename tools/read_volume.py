import sys
path = r"\\.\E:"
try:
    with open(path, "rb") as f:
        d = f.read(512)
    print("OK", d[:2], len(d))
except Exception as e:
    print(type(e).__name__, e)
