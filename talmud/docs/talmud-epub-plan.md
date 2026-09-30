# Talmud EPUB plan (handoff)

Status: **pilot build complete - device validation and reader integration remain.**
As of 2026-09-30, six pilot tractates have been fetched, normalized, generated,
and validated: Berakhot, Shabbat, Bava Metzia, Bava Batra, Sanhedrin, and Tamid.
All six EPUBs pass EPUBCheck and structural validation. The generated data is
kept locally under `work/` and `outputs/` and is ignored by git.

Mirrors `tanach/docs/tanach-epub.md`.
Read that and `tanach/outputs/reader-compatibility.md` first: the Talmud product
should behave like the Tanach product wherever this doc is silent.

## Goal

Talmud Bavli EPUBs with a finished product similar or identical to the Tanach
EPUBs: bilingual text, per-segment commentary asides, offline, e-ink friendly,
readable by the custom Flutter reader.

Final goal is the traditional 37 masechtos with Gemara. Build a small pilot first,
measure, then scale.

## Settled decisions

### Scope
- Talmud Bavli only, the traditional 37 masechtos with Gemara.
- Mishnah-only tractates: not included for now.
- Talmud Yerushalmi: not committed, not ruled out. Sefaria has a complete English
  translation (Guggenheimer, vocalized) and the Vilna commentaries (Korban HaEdah,
  Penei Moshe, Mareh HaPanim), so it is realistic as a later phase. Keep the
  pipeline and DB schema from assuming Bavli-only.

### Segment layout
- New independent segment `talmud/` with `docs/`, `work/`, `outputs/`, mirroring `tanach/`.
- Atomic unit: the Sefaria segment (e.g. `Berakhot 2a:1`), the analogue of a Tanach verse.
- Chapter unit: the **amud** (one XHTML document per side of a folio). Chosen over
  daf and perek because it keeps documents smallest; Tanach already hit multi-MB
  chapter XHTML and Talmud commentary is denser.
- TOC: one entry per amud (2a, 2b, 3a, ...). A nested daf > amud TOC is possible
  later without changing document granularity.
- Packaging: one EPUB per masechta. Oversized tractates (Shabbat, Eruvin, Bava
  Batra, Bava Metzia, Zevachim, Chullin, ...) are decided after the pilot gives
  real sizes; options are a more robust single file, reader-side changes, or
  splitting a masechta into a few EPUBs.

### Text
- Hebrew/Aramaic as a single stream, no special handling for the language mix.
- Nikud included by default. The reader has a setting that strips vowel points at
  render time. One build only, no unvocalized variant (reuses the reader's existing
  niqqud normalization used for search).
- English: William Davidson (Steinsaltz) translation exactly as Sefaria provides
  it. Missing segments stay blank, nothing invented, no substitute edition.

### Paragraphs and headings
- Default: Sefaria's own structure, a Hebrew paragraph then an English paragraph
  per segment. A Mishnah is just its own paragraph, no special label.
- Reader option: no paragraphs, text broken only at amud boundaries.
- When paragraphs are on, each segment gets an English-only reference heading such
  as `Berakhot 2a:1`. No bilingual heading like Tanach's verse row.

### Commentary
- Pilot set: **Rashi, Tosafot, and Steinsaltz's notes** ("Steinsaltz on [Tractate]":
  Background, Personalities, Halakha and similar; a separate Sefaria commentary
  source, not part of the translation).
- The Rashi slot must be handled generically. Some places have a different
  commentator standing in for Rashi (Bava Batra from 29a: Rashbam; Tamid: an
  anonymous commentator). Do not hardcode "Rashi".
- Same commentary presentation as Tanach: one heading per source per segment
  (e.g. `Rashi on Berakhot 2a:1`), separate paragraphs for each comment underneath.
- Cross-references to parallel sugyot: not now, maybe later.
- Reader picker order: Rashi first, then Tosafot, then everything else. This is a
  reader-side detail (numeric prefix or hardcoded order, whichever is simpler).

### Reader integration
- Generalize the Tanach-specific import/cache contract into one shared "study text"
  contract for Tanach and Talmud (segment/verse, amud/chapter, commentary asides
  are structurally the same). Decided by Claude at Levi's request. Build the
  content pipeline first, adapt the reader after.

### Licensing
- Same posture as Tanach: personal use only; private LFS or direct copy only;
  never the public repo or its releases.

## Open decision: commentary policy (to discuss after measuring)

Levi does not know the meforshim well and prefers a **blacklist** (include
everything except what is excluded) over a whitelist, but does not want long load
times. Neither can be settled without data.

Plan:
1. Run `inventory_report.py` to list every commentary source Sefaria links to the
   Bavli, with per-tractate coverage.
2. Show Levi that list with sizes so a blacklist can be chosen from real numbers.
3. Build the pilot with only Rashi + Tosafot + Steinsaltz notes and measure: bytes
   per amud, EPUB size, first-open import time, and page-turn behavior on the Bigme.
4. Add sources in batches (cheapest and most useful first), re-measuring after each,
   until the load budget is reached. If a blacklist is chosen, the resulting default
   set still has to fit the measured budget.

Coverage of non-core commentaries varies by tractate (for example Berakhot has
Meiri, Rashash and Milchemet Hashem linked; other tractates differ), so the policy
is applied per tractate.

## Pilot set

| Daf | Why |
|---|---|
| Berakhot 2a-2b | Opening sugya, dense Rashi and Tosafot, baseline |
| Bava Metzia 2a | Casuistic Nezikin sugya, dense Tosafot |
| Bava Batra 29a | Rashbam replaces Rashi from here to the end of the tractate |
| Sanhedrin 96b-97a | Aggadic content, good test for Steinsaltz notes |
| Tamid 25b | Smallest tractate, anonymous commentator in the Rashi slot |
| Shabbat 73a | The list of the 39 melachos, heavy commentary |

## Pipeline outline

Follow the Tanach stages and reuse scripts and validators wherever possible:

1. Inventory: Bavli refs, versions, linked commentary sources, sizes. ✅
2. Fetch and cache from Sefaria, reusing the Tanach fetch approach. ✅
3. Normalize into `talmud.sqlite` (segments, Hebrew/Aramaic, English, commentary
   segments, links). ✅ (build.py normalize stage)
4. Generate one EPUB per masechta, one XHTML document per amud, with the
   Tanach-style segment-to-index-to-source aside structure. ✅ (build.py generate stage)
5. Validate: EPUBCheck, structure and anchor checks, Hebrew integrity, link audit. ✅
6. Measure sizes and on-device load, then decide commentary expansion and
  large-tractate handling. ⏳ (requires device testing)
7. Package samples. ✅
8. Build and validate the remaining 31 masechtos. ⏳

## Reader work (after the pipeline)

- Shared study-text import contract for Tanach and Talmud.
- Nikud-strip display setting.
- Paragraph vs continuous-by-amud setting, with the `Berakhot 2a:1` heading in
  paragraph mode.
- Commentary picker ordering: Rashi, Tosafot, rest.

No Talmud reader integration has landed yet; `lib/` currently contains no
Talmud-specific references.

## Future scope

- More commentaries, per the commentary policy above.
- Cross-references to parallel sugyot.
- Talmud Yerushalmi.
- Mishnah-only tractates.

## Open Questions / Blockers

These were identified during implementation. The pilot pipeline is operational;
the items below affect the full build or reader integration.

### Current build findings

- The catalog has no Hebrew or English editions for Ta'anit, Mo'ed Katan, or
  Me'ilah. These need an alternate source or an explicit scope decision before
  the full 37-masechta build can be complete.
- The build report contains language-mismatch warnings for the French editions
  selected for Rashi on Berakhot and Tosafot on Berakhot. Verify the source
  selection before treating the pilot as final.

### OQ-1: Sefaria amud index structure

**Question:** Sefaria's Bavli text JSON may use either a flat list indexed by
amud position, a nested structure keyed by daf/side strings, or a dict keyed
by amud labels like `"2a"`. The `build.py` normalize stage currently assumes a
flat list indexed sequentially from 2a (the documented Bavli convention), using a
`_amud_sequence` generator that maps index 0 → 2a, 1 → 2b, 2 → 3a, etc.

**Resolution needed:** After running `sync.py inspect` to fetch a sample Berakhot
edition, inspect `d['text']` to confirm it is a flat list (not a dict keyed by
amud string). If Sefaria uses a different structure, update `normalize()` in
`build.py`.

**Action:** `python talmud/work/sync.py inspect` then `python -c "import json; d=json.load(open('talmud/work/cache/texts/<key>.json')); print(type(d['text']), len(d['text']), d['text'][0][:2])"`.

### OQ-2: Commentary schema addressing for Talmud

**Question:** Tanach commentary uses `sectionNames: ['Chapter', 'Verse']` to
address base text. Talmud commentary may use `['Daf', 'Line']` or `['Chapter',
'Verse']` (Sefaria sometimes uses the Tanach convention even for Talmud). The
`normalize()` commentary attachment logic in `build.py` assumes 1-based amud
index and segment index. If commentaries use a different addressing, notes may
fail to attach.

**Resolution needed:** After fetching a Rashi on Berakhot schema, inspect
`schema['sectionNames']` and confirm the indexing convention. Update the
attachment logic if needed.

**Action:** `python -c "import json; s=json.load(open('talmud/work/cache/schemas/<key>.json')); print(s.get('sectionNames'), s.get('schema',{}).get('sectionNames'))"`.

### OQ-3: Steinsaltz notes title in Sefaria

**Question:** The plan says the Steinsaltz commentary source is titled something
like "Steinsaltz on [Tractate]" in Sefaria, containing Background, Personalities,
Halakha notes. The `inventory.py` and `build.py` look for titles matching
`Steinsaltz on <masechta>`. If Sefaria uses a different title convention (e.g.
"Steinsaltz's Introduction to the Talmud", "William Davidson on Berakhot", or
per-section titles), the commentary inclusion logic will miss them.

**Resolution needed:** After `sync.py catalog`, scan `books.json` for any title
containing "Steinsaltz" that is not the main translation, and confirm the exact
titles to add to `inventory.py`'s PILOT_COMMENTARY_ORDER.

### OQ-4: Tamid anonymous commentator title

**Question:** The plan notes an "anonymous commentator" in the Rashi slot for
Tamid. `inventory.py` includes `RASHI_SLOT_ALIASES = {'Tamid': 'Pseudo-Rashi on
Tamid'}`. If Sefaria uses a different title, it will not be fetched.

**Resolution needed:** After `sync.py catalog`, search `books.json` for titles
referencing Tamid and commentary. Update `RASHI_SLOT_ALIASES` in `inventory.py`
and `build.py` if the title differs.

### OQ-5: Bava Batra Rashbam boundary

**Question:** The plan says "Rashbam replaces Rashi from Bava Batra 29a." The
`RASHI_SLOT_ALIASES` in `inventory.py` currently applies Rashbam for the whole
Bava Batra EPUB. This means the Rashi amudim before 29a would get Rashbam
labeled as the Rashi-slot commentary, which may be confusing.

**Assumption made:** For the pilot (which tests Bava Batra 29a only), this is
correct behavior. For the full build, consider:
- Including both "Rashi on Bava Batra" (for 2a–28b) AND "Rashbam on Bava Batra"
  (for 29a–end) and displaying both, with the reader showing whichever is non-empty
  for each amud.
- Or: split Bava Batra into two EPUBs at 29a.

This remains an open design question for the full build. The pilot is unaffected.

### OQ-6: Large tractate EPUB size

**Question:** The plan flags Shabbat, Eruvin, Bava Batra, Bava Metzia, Zevachim,
and Chullin as potentially oversized for a single EPUB file. The reader currently
has no per-EPUB size limit documented.

**Resolution needed after pilot:** Measure the Shabbat EPUB size (the largest
Bavli tractate) after the first full build. If it exceeds what the reader handles
comfortably (Tanach's largest is ~11 MB; Shabbat with full commentary may be
significantly larger), either:
- Raise the reader's EPUB size limit.
- Split oversized masechtos into Part 1 / Part 2 at a natural chapter boundary.

### Assumption log

- **A1:** Sefaria Bavli text JSON `d['text']` is a flat list of amudim, each a list
  of segment strings, indexed from 2a. (Standard Sefaria convention, not yet
  verified against a live fetch.)
- **A2:** Commentary uses 1-based amud index → amud label mapping consistent with
  the base text. (Will be verified by inspecting a Rashi schema after sync.)
- **A3:** `Pseudo-Rashi on Tamid` is the Sefaria title for the anonymous Tamid
  commentator. (Not yet verified; update `RASHI_SLOT_ALIASES` if wrong.)
