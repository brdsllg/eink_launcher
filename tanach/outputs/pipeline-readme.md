# Tanach EPUB pipeline

Current state: the full 39-book collection was rebuilt (revision 5, 22 September 2026) in
outputs/books/, and outputs/samples/ holds the nine chapter samples used for reader checks.
Python 3.11+ standard library is sufficient for downloading and building.
Use UTF-8 mode on Windows: `python -X utf8 ...`.
Run the commands below from the tanach/ segment root, which contains work/ and outputs/.

Directory layout is intentional: scripts in work/, configuration and deliverables in outputs/.
The raw cache in work/cache/ and the normalized database in work/tanach.sqlite are the fastest
way to rebuild offline.

Rebuild from the existing cache:
    python -X utf8 work/build.py

Redraw EPUBs from the existing SQLite database after a presentation-only edit:
    python -X utf8 work/regenerate.py
    python -X utf8 work/regenerate.py --book Obadiah  # one-book trial

The one-book command leaves full-coverage.json unchanged. ZIP timestamps can change on a
rebuild even when member contents are identical; refresh package checksums after acceptance.

Audit chapter XHTML compression on the current books:
    python -X utf8 work/audit_chapter_compression.py --level 6

Package the current deliverables:
    python -X utf8 work/package_full.py      # checksums + outputs/tanach-39-epubs.zip
    python -X utf8 work/package_samples.py   # guides + outputs/tanach-samples.zip + tanach-pipeline.zip

To download into a fresh workspace, retain outputs/source-selection.json and run:
    python -X utf8 work/sync.py catalog
    python -X utf8 work/sync.py inspect
    python -X utf8 work/sync.py schemas
    python -X utf8 work/plan.py
    python -X utf8 work/sync.py texts
    python -X utf8 work/sync.py links
    python -X utf8 work/build.py

The inspect step also caches the current link-file listing. Download failures are recorded in work/cache/.
Do not run inventory.py over an edited source-selection.json: it is the initial catalog-discovery script and will regenerate that file.
Source status and per-edition decisions in the manifest control the selection. Explicit edition decisions override the discovery rules.
After source-selection changes, run plan.py, sync.py texts, and build.py to update the cache and normalized database.
English commentary variants without established provenance remain pending; a pending edition is not downloaded by subsequent plan runs.

Validation requires EPUBCheck and a Java runtime, extracted under work/tools/ (work/get_validation_tools.py re-downloads them if missing).
Run work/validate.py over outputs/books, then work/test_pipeline.py, work/check_heading_presentation.py, and work/check_grouped_notes.py. work/test_pipeline.py also uses the independently cached tanach.us Ruth XML for its evidence check; work/visual-check.cjs renders work/preview/ with the bundled Playwright runtime.
The exact download metadata and SHA-256 of each source are kept beside cached files; link downloads are pinned to bucket object generations.
The build does not access the network.

work/legacy/ holds historical one-shot migrations (revise_*, refine_*, apply_whitelist.py, document_grouped_format.py, update_heading_presentation.py) plus an obsolete coverage snapshot. Do not rerun them blindly: some overwrite current preferences or duplicate edits. Make changes directly to the current generator, configuration, and documentation.
