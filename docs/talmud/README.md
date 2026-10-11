# Talmud EPUB pipeline

This segment of the repository produces Talmud Bavli EPUBs for personal use on the
Bigme e-ink device. It mirrors `tanach/` in layout and tooling and follows the same
reader contract; where this folder is silent, `docs/tanach/docs/tanach-epub.md` and
`tanach/outputs/reader-compatibility.md` apply. That second file stays in the `tanach/`
segment because the pipeline rewrites it; its readable summary is in
`docs/tanach/outputs/reader-compatibility.md`.

**Status (9 Oct 2026):** the six-tractate pilot is built and passes EPUBCheck and
link checks. Inventory now uses the blacklist policy: all 1,134 Bavli
commentaries in Hebrew/English (1,445 files planned), one masechta at a time,
batched downloads. 6 Oct device findings got code fixes (Continuous crash,
commentary order, inventory Finding F) that need rebuilt books + HiBreak
recheck. Still to do: checking on the Bigme, downloading + building the other
31 tractates with all commentaries, and the measure/decision gate.

## What it produces

One EPUB per tractate (masechta), one XHTML document per side of a page (amud).
Each has Hebrew/Aramaic with the William Davidson (Steinsaltz) English translation
and commentaries per the blacklist policy (Oct 2026): every Bavli commentary
Sefaria offers in Hebrew or English (pilot books so far contain the cached
Rashi, Tosafot, and Steinsaltz notes; the rest download next).

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
python talmud/work/inventory.py                     # 2. source-selection manifest (all commentaries)
python talmud/work/sync.py schemas --masechta Berakhot   # 3. steady: one book at a time
python talmud/work/sync.py texts --masechta Berakhot
python talmud/work/sync.py links
python talmud/work/build.py --pilot                 # 4. build the pilot EPUBs
python talmud/work/build.py --masechta Berakhot     # steady single-book normalize + EPUB
python talmud/work/build.py --masechta Berakhot --normalize-only  # DB only, no EPUB
python talmud/work/validate.py --pilot              # 5. validate
python talmud/work/package_samples.py               # 6. package pilot samples
python talmud/work/build.py                         # full 37-tractate build, after measuring
python talmud/work/regenerate.py --masechta Berakhot  # rebuild one tractate from the database
```

## Next steps, in order

1. **Check on the Bigme:** headings, one title per commentary source, Contents links,
   settings wording (checklist in `docs/reader-device-findings.md`).
2. **Scaling work (done 9 Oct in builder):** per-masechta normalize with freed
   memory, batched downloads (50/batch, 4 workers, resumable), single-book
   `--masechta` for sync + build, single-book reports that never clobber the
   full report. Remaining: per-source search index + picker grouping.
3. **Measure** one big tractate with 2, then about 5, then all sources: EPUB size,
   largest amud, first-open time, peak memory, page-turn speed, search speed.
4. **Decide** from those numbers whether to keep EPUB packaging or have the pipeline
   write a SQLite file directly.
5. Build and validate the remaining 31 tractates.

Also open: the French-edition warnings for Rashi and Tosafot on Berakhot are now
fixed by the English+Hebrew-only rule (Oct 2026, now extended to test/abridged
and [fr]/[de] at inventory time); commentary-source discovery is fixed by the
books.json suffix + Bavli-category scan (1,134 sources, Oct 2026 — verify by
comparing counts after re-running inventory). The three formerly "missing" tractates
(Taanit, Moed Katan, Meilah — Sefaria's spelling) are present with Hebrew and
William Davidson English; the old gap was a spelling mismatch, now fixed.

## Reader integration

The reader recognizes Talmud EPUBs as study books (translation and commentary
controls, SQLite cache), and its settings read "Talmud language" and "after each
segment". Implemented Oct 2026: a setting to hide vowel points, a
paragraph-versus-continuous setting (continuous merges body paragraphs, breaks
only at headings/amud boundaries), commentary picker ordering (Rashi/Rashbam/
Mefaresh, Tosafot, then the rest alphabetically), and search that skips
commentary candidates when no source is selected (SQLite v6 split
base/commentary index; final projection still applies the exact filter).
Still to do: picker grouping/search box for dozens of sources.

## Licensing

Personal use only. Never commit generated EPUBs or raw Sefaria data to a public
repository or its releases; use private LFS or a direct file copy. Edition and license
details are recorded in `outputs/source-selection.json`; personal use is not a
blanket license decision.
