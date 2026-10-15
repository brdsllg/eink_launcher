# Talmud EPUB plan

**Status (6 Oct 2026):** pilot built and validated for six tractates (Berakhot,
Shabbat, Bava Metzia, Bava Batra, Sanhedrin, Tamid). The reader's study-book support
covers Talmud. Code fixes 6 Oct (Continuous crash, commentary order, inventory
Finding F) need rebuilt books + Bigme recheck. Device checking, the other 31 tractates, and scale-up remain. Generated
data is local under `work/` and `outputs/` and ignored by git.

Read `docs/tanach/docs/tanach-epub.md` first, plus
`tanach/outputs/reader-compatibility.md` (the pipeline's own copy, since the pipeline
rewrites it): Talmud should behave like Tanach wherever this document is silent.

## Goal

Talmud Bavli EPUBs matching the Tanach ones: bilingual text, per-segment commentary,
fully offline, e-ink friendly, readable by the custom reader. Final scope is the
traditional 37 tractates with Gemara. Pilot first, measure, then scale.

## Settled decisions

### Scope and layout

- **Scope:** Talmud Bavli only. Mishnah-only tractates are not included for now.
  Talmud Yerushalmi is neither committed nor ruled out (Sefaria has an English
  translation and the main commentaries), so the pipeline and database must not
  assume Bavli only.
- **Structure:** an independent segment, `talmud/`, with `docs/`, `work/`, `outputs/`,
  like `tanach/`.
- **Units:** the Sefaria segment (such as `Berakhot 2a:1`) is the verse equivalent.
  One XHTML document per **amud**, chosen over daf or chapter to keep documents
  smallest. One contents entry per amud; a daf > amud nesting could come later.
- **Packaging:** one EPUB per tractate. Oversized tractates (Shabbat, Eruvin, Bava
  Batra, Bava Metzia, Zevachim, Chullin, and others) are decided after real sizes are
  measured: a sturdier single file, reader changes, or a split into a few EPUBs.

### Text

- Hebrew/Aramaic as one stream with no special handling of the mix.
- Vowel points included: the base text is Sefaria's **William Davidson
  Edition – Vocalized Aramaic** (all 37 masechtos carry it; Berakhot holds
  ~227k marks in U+0591–05C7, zero cantillation — verified Oct 2026 from
  the export bucket). The old pipeline preferred the unpointed Aramaic
  edition, which is why the reader toggle did nothing on Talmud.
  A reader setting hides vowels at display time; there is only one build.
  Cantillation is stripped (none present in this edition).
- English: William Davidson (Steinsaltz) translation exactly as Sefaria has it.
  Missing segments stay blank: nothing invented, no substitute edition.

### Paragraphs and headings

- Default: a Hebrew paragraph then an English paragraph per segment, following
  Sefaria's structure. A Mishnah is simply its own paragraph.
- Reader option: no paragraphs, with breaks only at amud boundaries.
- With paragraphs on, each segment has an **English-only** heading such as
  `Berakhot 2a:1`.

### Commentary

- **Pilot set:** Rashi, Tosafot, and the Steinsaltz notes ("Steinsaltz on
  [Tractate]": Background, Personalities, Halakha, and similar), a separate Sefaria
  commentary, not part of the translation. Levi chose on 5 Oct 2026 to keep the
  Steinsaltz notes.
- **Blacklist, not whitelist:** include every Sefaria commentary on the Bavli across
  all 37 tractates; the blacklist starts empty. Levi does not know the commentators
  well and prefers this approach, but does not want long load times, so the final
  default set must fit the measured device budget.
- **The Rashi slot is generic.** Some places use a different commentator (Rashbam
  on Bava Batra from 29a; an anonymous commentator on Tamid). Never hardcode "Rashi".
- **Presentation:** same as Tanach: one heading per source per segment (such as
  `Rashi on Berakhot 2a:1`), then each comment as its own paragraph.
- Cross-references to parallel passages: not now, maybe later.
- Picker order in the reader: Rashi, Tosafot, then the rest.

### Reader integration

One shared "study text" contract serves Tanach and Talmud. The content pipeline came
first; the reader was adapted afterwards.

### Licensing

Same as Tanach: personal use only; private LFS or direct copy; never the public
repository or its releases.

## Pilot test spots

| Amud | Why |
|---|---|
| Berakhot 2a–2b | Opening passage, dense Rashi and Tosafot, baseline |
| Bava Metzia 2a | Case-law passage, dense Tosafot |
| Bava Batra 29a | Rashbam replaces Rashi from here |
| Sanhedrin 96b–97a | Narrative content; good for Steinsaltz notes |
| Tamid 25b | Smallest tractate; anonymous commentator in the Rashi slot |
| Shabbat 73a | The 39 categories of work; heavy commentary |

## Pipeline status

| Stage | State |
|---|---|
| 1. Inventory: Bavli refs, editions, commentary sources, sizes | Done |
| 2. Fetch and cache from Sefaria | Done |
| 3. Normalize into `talmud.sqlite` | Done |
| 4. Generate one EPUB per tractate, one document per amud | Done |
| 5. Validate: EPUBCheck, anchors, Hebrew integrity, link audit | Done for the pilot |
| 6. Measure sizes and on-device load; decide commentary expansion and large tractates | **Next** (needs the device) |
| 7. Package samples | Done |
| 8. Build and validate the other 31 tractates | Pending |

## Reader work

Done: the shared study-text contract (the reader accepts the Talmud dialect, so the
books open as study text with commentary-source, commentary-language, and translation
controls and the SQLite cache); "Talmud language" option with the "Selected
commentary appears after each segment…" helper sentence. The
Parshah/Aliyot toggle stays hidden because Talmud has no Parshah contents.

Implemented Oct 2026: a setting to hide vowel points; a paragraph-versus-continuous
setting with the `Berakhot 2a:1` heading kept; picker ordering (Rashi/Rashbam/
Mefaresh, Tosafot, rest alphabetical); search skips commentary candidates when no
source is selected (SQLite v6 `base_search_text`/`commentary_search_text`;
per-source full-text index still future). Details and device findings are in
[reader-device-findings.md](reader-device-findings.md).

## Open questions

- **Resolved Oct 2026 — the three "missing" tractates are present.** Sefaria
  spells them without apostrophes (Taanit, Moed Katan, Meilah). The earlier
  "missing" report was a spelling mismatch in our inventory, not a Sefaria gap:
  all three have Hebrew (Wikisource + William Davidson Aramaic) and William
  Davidson English. The inventory now uses Sefaria's spelling; the traditional
  Ta'anit / Mo'ed Katan / Me'ilah remain display aliases only.
- **Resolved Oct 2026 — English + Hebrew only.** French (Berakhot Rashi/Tosafot
  `[fr]`), German, and all other non-HE/EN editions are now skipped at inventory
  time and never downloaded or built. The old language-mismatch warnings should
  not recur.
- **Commentary addressing:** the build assumes commentary uses the same amud and
  segment numbering as the base text. In plain words: when Rashi says something
  about "Berakhot 2a, line 1", we trust that Sefaria numbers Rashi's comments
  the same way it numbers the main text, so the note lands on the right
  paragraph. Link audits pass and spot checks look right, but nobody has opened
  Sefaria's layout files and confirmed this numbering rule directly. Still open.
- **Resolved Oct 2026 — Tamid Rashi slot is "Mefaresh on Tamid".** Levi confirmed
  the anonymous Vilna commentary; `RASHI_SLOT_ALIASES` now maps Tamid to
  `Mefaresh on Tamid` (Hebrew, Vilna Edition).
- **Bava Batra Rashi slot:** in plain words — the first half of Bava Batra was
  explained by Rashi, the second half (from page 29a) by his grandson Rashbam.
  Both exist in Sefaria. For the full build we either show whichever one exists
  on each page, or split the book at 29a. The pilot is unaffected. Still open.
- **Large tractates:** in plain words — some books (Shabbat, Bava Batra, Bava
  Metzia, and other long ones) may become very large files once every commentary
  is included. Tanach's biggest book is about 11 MB; Shabbat with full
  commentary could be much bigger. We measure Shabbat first, then either raise
  the reader's size limit or split the book into parts at a natural chapter
  break. Still open (needs the device measurement).
- **Commentary budget:** in plain words — after the pilot measurements, we add
  extra commentators in small batches (cheapest and most useful first) and
  re-measure each time, because some tractates have many more commentaries than
  others. `inventory_report.py` lists every commentary Sefaria links to the Bavli.
  Still open (needs the measurements).

## Measurements (10 Oct 2026, HiBreak, release APK incl. sidecar-subfolder support)

First full-commentary big-tractate run: **Bava Batra** (largest pilot book),
all 38 blacklist-policy commentary sources (47 edition files). Built with the
uncommitted steady one-masechta path (`sync.py --masechta`, `build.py
--masechta`); per-book report in `talmud/outputs/build-report-bava-batra.json`.
Device file kept as `bava-batra-full.epub` next to the pilot books.

| Measure | Full Bava Batra | Pilot Bava Batra (for reference) |
|---|---|---|
| EPUB size | 10,082,328 bytes (~9.6 MiB) | 4,156,256 bytes |
| Segments / notes | 3,804 / 34,030 | ~12,636 notes |
| Largest amud | 4b, 432,008 bytes XHTML (amudim total 48.5 MB uncompressed) | — |
| EPUBCheck | clean (see fix note below) | clean |
| Sidecar (`study/`, laptop-built) | 70,479,872 bytes, fingerprint verified = EPUB SHA-256 | — |
| Cold first open (no sidecar, on-device import) | ~2.5–3 min (intent 23:33:48, Loading at 23:34/23:35, content by 23:36; coarse screencap bounds) | 21 s (6 Oct, pilot) |
| Memory at import completion | PSS 154 MB, RSS 245 MB (peak *during* import not captured) | — |
| Warm reopen (force-stop + intent) | instant (activity 1.36 s, content rendered, no Loading) | 1–2 s |
| Page turns (D-pad + tap) | work, bilingual segments render (2a:2–2b:3 verified) | pass |
| TOC screen | renders, 27 pages, Daf 2a link jumps p1 → p17 correctly | pass |
| Search for a common word | **not measured** (search UI would not open via adb taps) | — |

- **Builder fix (uncommitted, `talmud/work/build.py`):** Sefaria embeds raw
  U+001F runs in some commentaries; first full build failed EPUBCheck (2
  fatals RSC-016 + 78 cascading RSC-012). Added `strip_controls()` at the
  `clean()`/`plaintext()` chokepoints; rebuilt book validates clean.
  `tanach/work/build.py` has the same latent exposure (no control stripping)
  — flagged, not yet fixed/verified.
- **Reader finding (minor):** the book's own Contents page (`nav.xhtml`)
  renders heading-only in the reading view; the native TOC screen is fine.
- **Footer page totals are progressive estimates**, not stable counts
  (portrait 1148 → 1731; landscape 66 → 566 → 1107 → 1884 as background
  pagination converges). Do not quote them as measurements.
- **APK size note:** universal `flutter build apk --release` is now 101 MB
  (3 ABIs incl. pdfium); owner's 8 Oct build was 46 MB. Consider
  `--split-per-abi` or arm64-only for device distribution.
- **Device state left behind:** this tab is in Landscape (automation could not
  flip the toggle back — one owner tap restores Portrait); pilot books
  untouched; `bava-batra-full.epub` + `study/bava-batra-full.study.sqlite`
  on device; no logcat exceptions this pass.
- Still open for the decision gate: peak memory *during* import, page-turn
  milliseconds, search timing with many sources selected, and the
  repeat for Shabbat.

## Resolved

- **Amud numbering:** Sefaria's arrays start at 1a, not 2a. The build now labels from
  that, records each tractate's first amud in the build report, and warns if a pilot
  tractate does not open on its known first amud (Berakhot 2a, Tamid 25b, the rest
  2a). Verified 5 Oct 2026.
- **Steinsaltz title and inclusion:** titles follow "Steinsaltz on [Tractate]" and are
  included; the decision to keep them stands.

## Future scope

More commentaries per the budget above; cross-references to parallel passages;
Talmud Yerushalmi; Mishnah-only tractates.
