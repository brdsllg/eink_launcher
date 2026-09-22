import hashlib
import json
import zipfile
from pathlib import Path

from sync import ROOT


out = ROOT / "outputs"
books = out / "books"
epubs = sorted(books.glob("*.epub"))
assert len(epubs) == 39, ("Expected 39 EPUBs", len(epubs))

validation = json.loads((out / "full-validation-results.json").read_text())
assert len(validation) == 39
assert all(row["epubcheck_exit"] == 0 and row["structure"] == "pass" for row in validation)

checksums = []
for path in epubs:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    checksums.append({"file": path.name, "bytes": path.stat().st_size, "sha256": digest})
(out / "full-checksums.json").write_text(
    json.dumps(checksums, indent=2) + "\n", encoding="utf-8"
)

bundle = out / "tanach-39-epubs.zip"
with zipfile.ZipFile(bundle, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in epubs:
        archive.write(path, "books/" + path.name)
    for name in (
        "FULL-BUILD-README.md",
        "full-coverage.json",
        "full-validation-results.json",
        "full-checksums.json",
        "build-report.json",
        "selected-commentaries.md",
        "source-selection.json",
    ):
        archive.write(out / name, name)

bundle_hash = hashlib.sha256(bundle.read_bytes()).hexdigest()
(out / "tanach-39-epubs.zip.sha256").write_text(
    f"{bundle_hash}  {bundle.name}\n", encoding="ascii"
)
print(f"Packaged {len(epubs)} EPUBs: {bundle} ({bundle.stat().st_size} bytes)")
print(f"SHA-256: {bundle_hash}")
