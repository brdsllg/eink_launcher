# Talmud Bavli source summary

A condensed, readable version of the source-selection manifest. The full machine
record is `source-selection.json`. Note that `inventory.py` regenerates the original
`source-review.md`, so this tidy version is a reference, not something the pipeline
keeps. Edition licenses, actual amud coverage, and commentary attachment still need
verifying after each fetch.

## Confirmed preferences

37 tractates of Talmud Bavli with Gemara; Hebrew with vowel points; William Davidson
(Steinsaltz) English; Rashi, Tosafot, and Steinsaltz notes for the pilot; personal
use; Bigme.

**Pilot tractates:** Berakhot, Shabbat, Bava Metzia, Bava Batra, Sanhedrin, Tamid.
**Pilot test spots:** Berakhot 2a and 2b, Bava Metzia 2a, Bava Batra 29a, Sanhedrin
96b and 97a, Tamid 25b, Shabbat 73a.

## Edition coverage

Every tractate has Hebrew editions (3 or 4 each) and a William Davidson English
edition (3 to 10 English editions in all), **including Taanit, Moed Katan, and
Meilah** (Sefaria's spelling — the earlier "missing" report was a spelling
mismatch, fixed Oct 2026).

## Commentary titles included in the pilot manifest (111)

| Commentary | Tractates covered |
|---|---|
| Rashi | 36 (every tractate except Tamid, where Mefaresh fills the Rashi slot) |
| Rashbam | Bava Batra (the Rashi slot there) |
| Mefaresh | Tamid (anonymous Vilna commentary in the Rashi slot, confirmed Oct 2026) |
| Tosafot | 36 (every tractate except Tamid, which has no Tosafot) |
| Steinsaltz | 37 (all tractates including Tamid) |

Commentary downloads and builds are English + Hebrew only (Oct 2026). A further
13 titles are "pending review". The full list of titles is in
`source-selection.json`.

## Download plan

282 edition files (base texts plus pilot commentaries, English + Hebrew only).
Oct 2026 sync fetched all 282 with 0 failures; all 148 schemas fetch with 0
failures.

## Next steps

1. Check this summary against `source-selection.json`.
2. Fetch (`sync.py schemas`, `texts`, `links`), build, and validate as in
   `../HOW-TO-SYNC.md`.
3. Measure EPUB sizes and first-open times on the Bigme.
4. Expand commentary per the policy in `../docs/talmud-epub-plan.md`.
