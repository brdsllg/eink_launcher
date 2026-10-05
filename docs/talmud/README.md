# Talmud EPUB pipeline

This segment of the repository produces Talmud Bavli EPUBs for personal use on the
Bigme e-ink device. It mirrors `tanach/` in layout and tooling and follows the same
reader contract; where this folder is silent, `tanach/docs/tanach-epub.md` and
`tanach/outputs/reader-compatibility.md` apply.

**Status (5 Oct 2026):** the six-tractate pilot is built and passes EPUBCheck and
link checks. Problems found on the device were fixed and re-verified on the computer.
Still to do: checking on the Bigme, building the other 31 tractates, and the
scale-up work.

## What it produces

One EPUB per tractate (masechta), one XHTML document per side of a page (amud).
Each has Hebrew/Aramaic with the William Davidson (Steinsaltz) English translation
and, as the pilot commentary set, Rashi, Tosafot, and the Steinsaltz notes.

- **Pilot tractates:** Berakhot, Shabbat, Bava Metzia, Bava Batra, Sanhedrin, Tamid.
  Berakhot opens at 2a and Tamid at 25b.
- **Final scope:** the traditional 37 tractates of Talmud Bavli with Gemara.
- Generated files are local and not tracked by git (see Licensing).

## Folder layout

| Path | Purpose |
|---|---|
| `docs/talmud-epub-plan.md` | Settled decisions, open questions, plan |
| `docs/reader-device-findings.md` | Problems found on the device, their status, and scale-up analysis |
| `HOW-TO-SYNC.md` | Step-by-step data download and build instructions |
| `work/sync.py` | Download and cache Sefaria data |
| `work/inventory.py` | Build the source-selection manifest |
| `work/build.py` | Normalize into SQLite and generate EPUBs |
| `work/validate.py` | EPUBCheck plus structure checks |
| `work/regenerate.py` | Rebuild from the existing database |
| `work/package_samples.py` | Package the pilot sample set |
| `work/audit_hebrew.py` | Check no cantillation marks remain |
| `work/audit_links.py` | Check note and chapter links resolve |
| `work/inventory_report.py` | Per-tractate commentary coverage table |
| `work/talmud.sqlite` | Normalized intermediate database (generated) |
| `outputs/` | Generated EPUBs, reports, and ZIPs |

## Commands

Run from the repository root with `python talmud/work/<script>.py`. The full
step-by-step version, with troubleshooting, is in [HOW-TO-SYNC.md](HOW-TO-SYNC.md).

```powershell
python talmud/work/sync.py catalog                  # 1. catalog
python talmud/work/inventory.py                     # 2. source-selection manifest
python talmud/work/sync.py schemas                  # 3. fetch texts and commentary
python talmud/work/sync.py texts
python talmud/work/sync.py links
python talmud/work/build.py --pilot                 # 4. build the pilot EPUBs
python talmud/work/validate.py --pilot              # 5. validate
python talmud/work/package_samples.py               # 6. package pilot samples
python talmud/work/build.py                         # full 37-tractate build, after measuring
python talmud/work/regenerate.py --masechta Berakhot  # rebuild one tractate from the database
```

## Next steps, in order

1. **Check on the Bigme:** headings, one title per commentary source, Contents links,
   settings wording (checklist in `docs/reader-device-findings.md`).
2. **Scaling work:** index comments per source instead of rescanning for every link
   row, build one tractate at a time, keep one edition per language.
3. **Measure** one big tractate with 2, then about 5, then all sources: EPUB size,
   largest amud, first-open time, peak memory, page-turn speed, search speed.
4. **Decide** from those numbers whether to keep EPUB packaging or have the pipeline
   write a SQLite file directly.
5. Build and validate the remaining 31 tractates.

Also open: Ta'anit, Mo'ed Katan, and Me'ilah have no Hebrew or English editions in
Sefaria's catalog and need an alternate source or a scope decision; the French-edition
warnings for Rashi and Tosafot on Berakhot need checking; commentary-source discovery
may be incomplete (see the findings doc).

## Reader integration

The reader recognizes Talmud EPUBs as study books (translation and commentary
controls, SQLite cache), and its settings read "Talmud language" and "after each
segment". Reader work still to do: a setting to hide vowel points, a
paragraph-versus-continuous setting, commentary picker ordering (Rashi, Tosafot,
then the rest; currently alphabetical), and limiting search to the selected sources.

## Licensing

Personal use only. Never commit generated EPUBs or raw Sefaria data to a public
repository or its releases; use private LFS or a direct file copy. Edition and license
details are recorded in `outputs/source-selection.json`; personal use is not a
blanket license decision.
