# Talmud EPUB plan (handoff)

Status: planning complete for the pilot; no pipeline code written yet.
Mirrors `tanach/docs/tanach-epub.md`. Read that and `tanach/outputs/reader-compatibility.md` first: the Talmud product should behave like the Tanach product wherever this doc is silent.

## Goal

Talmud Bavli EPUBs with a finished product similar or identical to the Tanach EPUBs: bilingual text, per-segment commentary asides, offline, e-ink friendly, readable by the custom Flutter reader.

Final goal is the traditional 37 masechtos with Gemara. Build a small pilot first, measure, then scale.

## Settled decisions

### Scope
- Talmud Bavli only, the traditional 37 masechtos with Gemara.
- Mishnah-only tractates: not included for now.
- Talmud Yerushalmi: not committed, not ruled out. Sefaria has a complete English translation (Guggenheimer, vocalized) and the Vilna commentaries (Korban HaEdah, Penei Moshe, Mareh HaPanim), so it is realistic as a later phase. Keep the pipeline and DB schema from assuming Bavli-only.

### Segment layout
- New independent segment `talmud/` with `docs/`, `work/`, `outputs/`, mirroring `tanach/`.
- Atomic unit: the Sefaria segment (e.g. `Berakhot 2a:1`), the analogue of a Tanach verse.
- Chapter unit: the **amud** (one XHTML document per side of a folio). Chosen over daf and perek because it keeps documents smallest; Tanach already hit multi-MB chapter XHTML and Talmud commentary is denser.
- TOC: one entry per amud (2a, 2b, 3a, ...). A nested daf > amud TOC is possible later without changing document granularity.
- Packaging: one EPUB per masechta. Oversized tractates (Shabbat, Eruvin, Bava Batra, Bava Metzia, Zevachim, Chullin, ...) are decided after the pilot gives real sizes; options are a more robust single file, reader-side changes, or splitting a masechta into a few EPUBs.

### Text
- Hebrew/Aramaic as a single stream, no special handling for the language mix.
- Nikud included by default. The reader has a setting that strips vowel points at render time. One build only, no unvocalized variant (reuses the reader's existing niqqud normalization used for search).
- English: William Davidson (Steinsaltz) translation exactly as Sefaria provides it. Missing segments stay blank, nothing invented, no substitute edition.

### Paragraphs and headings
- Default: Sefaria's own structure, a Hebrew paragraph then an English paragraph per segment. A Mishnah is just its own paragraph, no special label.
- Reader option: no paragraphs, text broken only at amud boundaries.
- When paragraphs are on, each segment gets an English-only reference heading such as `Berakhot 2a:1`. No bilingual heading like Tanach's verse row.

### Commentary
- Pilot set: **Rashi, Tosafot, and Steinsaltz's notes** ("Steinsaltz on [Tractate]": Background, Personalities, Halakha and similar; a separate Sefaria commentary source, not part of the translation).
- The Rashi slot must be handled generically. Some places have a different commentator standing in for Rashi (Bava Batra from 29a: Rashbam; Tamid: an anonymous commentator). Do not hardcode "Rashi".
- Same commentary presentation as Tanach: one heading per source per segment (e.g. `Rashi on Berakhot 2a:1`), separate paragraphs for each comment underneath.
- Cross-references to parallel sugyot: not now, maybe later.
- Reader picker order: Rashi first, then Tosafot, then everything else. This is a reader-side detail (numeric prefix or hardcoded order, whichever is simpler).

### Reader integration
- Generalize the Tanach-specific import/cache contract into one shared "study text" contract for Tanach and Talmud (segment/verse, amud/chapter, commentary asides are structurally the same). Decided by Claude at Levi's request. Build the content pipeline first, adapt the reader after.

### Licensing
- Same posture as Tanach: personal use only; private LFS or direct copy only; never the public repo or its releases.

## Open decision: commentary policy (to discuss after measuring)

Levi does not know the meforshim well and prefers a **blacklist** (include everything except what is excluded) over a whitelist, but does not want long load times. Neither can be settled without data.

Plan:
1. Write an inventory script (analogue of `tanach/work/inventory.py`) that lists every commentary source Sefaria links to the Bavli, with per-tractate coverage and total text size per source.
2. Show Levi that list with sizes so a blacklist can be chosen from real numbers.
3. Build the pilot with only Rashi + Tosafot + Steinsaltz notes and measure: bytes per amud, EPUB size, first-open import time, and page-turn behavior on the Bigme.
4. Add sources in batches (cheapest and most useful first), re-measuring after each, until the load budget is reached. If a blacklist is chosen, the resulting default set still has to fit the measured budget.

Coverage of non-core commentaries varies by tractate (for example Berakhot has Meiri, Rashash and Milchemet Hashem linked; other tractates differ), so the policy is applied per tractate.

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

Follow the Tanach stages and reuse scripts and validators wherever possible (`sync.py`, `build.py`, `validate.py`, `audit_links.py`, `audit_hebrew.py`, `package_samples.py`):

1. Inventory: Bavli refs, versions, linked commentary sources, sizes.
2. Fetch and cache from Sefaria, reusing the Tanach fetch approach. Sefaria's public database export is a candidate bulk source to evaluate.
3. Normalize into `talmud.sqlite` (segments, Hebrew/Aramaic, English, commentary segments, links).
4. Generate one EPUB per masechta, one XHTML document per amud, with the Tanach-style verse/segment-to-index-to-source aside structure.
5. Validate: EPUBCheck, structure and anchor checks, Hebrew integrity, link audit.
6. Measure sizes and on-device load, then decide commentary expansion and large-tractate handling.
7. Package samples, then the full set.

## Reader work (after the pipeline)

- Shared study-text import contract for Tanach and Talmud.
- Nikud-strip display setting.
- Paragraph vs continuous-by-amud setting, with the `Berakhot 2a:1` heading in paragraph mode.
- Commentary picker ordering: Rashi, Tosafot, rest.

## Future scope

- More commentaries, per the commentary policy above.
- Cross-references to parallel sugyot.
- Talmud Yerushalmi.
- Mishnah-only tractates.
