"""Builds dist/rls_configurator.zip (mod files at the zip root, ready for BeamNG)."""
import os
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
CONTENT = ("lua", "ui", "gameplay")
OUT = os.path.join(ROOT, "dist", "rls_configurator.zip")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    for top in CONTENT:
        for base, _, files in os.walk(os.path.join(ROOT, top)):
            for name in sorted(files):
                full = os.path.join(base, name)
                z.write(full, os.path.relpath(full, ROOT).replace(os.sep, "/"))
print("built", OUT)
