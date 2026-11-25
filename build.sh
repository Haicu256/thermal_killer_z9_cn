#!/usr/bin/env bash
set -euo pipefail

OUT="thermal_killer_z9(CN)_v1.1.zip"
rm -f "$OUT"
python3 - <<'PY'
import zipfile, os

out_zip = "thermal_killer_z9(CN)_v1.1.zip"
include_files = [
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "README.md",
    "action.sh",
    "module.prop",
    "sepolicy.rule",
    "service.sh",
    "tk_ctl.sh",
    "uninstall.sh",
    "webroot/index.html",
]

with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
    for rel in include_files:
        zi = zipfile.ZipInfo(rel)
        zi.compress_type = zipfile.ZIP_DEFLATED
        mode = 0o755 if rel.endswith(".sh") or rel.endswith("update-binary") else 0o644
        zi.external_attr = (mode & 0xFFFF) << 16
        with open(rel, "rb") as f:
            z.writestr(zi, f.read())

print(f"Built {out_zip} ({os.path.getsize(out_zip)} bytes)")
PY
sha256sum "$OUT"
