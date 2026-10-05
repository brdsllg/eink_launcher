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
edition (3 to 10 English editions in all), **except Ta'anit, Mo'ed Katan, and
Me'ilah, which have none** and need an alternate source or a scope decision.

## Commentary titles included in the pilot manifest (101)

| Commentary | Tractates covered |
|---|---|
| Rashi | 33 (every tractate except Ta'anit, Mo'ed Katan, Me'ilah, Tamid) |
| Rashbam | Bava Batra (the Rashi slot there) |
| Tosafot | The same 33 as Rashi |
| Steinsaltz | 34 (those 33 plus Tamid) |

Tamid has no Rashi or Tosafot title in the manifest; its Rashi-slot substitute is
still to be confirmed. A further 13 titles are "pending review". The full list of
titles is in `source-selection.json`.

## Download plan

264 edition files (base texts plus pilot commentaries). The 5 Oct 2026 sync fetched all
264.

## Next steps

1. Check this summary against `source-selection.json`.
2. Fetch (`sync.py schemas`, `texts`, `links`), build, and validate as in
   `../HOW-TO-SYNC.md`.
3. Measure EPUB sizes and first-open times on the Bigme.
4. Expand commentary per the policy in `../docs/talmud-epub-plan.md`.
