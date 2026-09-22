# Complete 39-book Tanach EPUB collection

Built 17 September 2026 from pinned Sefaria public exports using the approved
source-selection manifest and revision-5 presentation contract.

## Contents

- 39 EPUBs in canonical configured order, one complete EPUB per book
- 23,206 Hebrew verses (vowels, no cantillation)
- Approved English translations, preferring Metsudah and falling back to Koren
- 203,039 unique selected commentary segments, presented in 112,694
  source/verse groups
- Chapter-only navigation, offline notes, edition metadata, source URLs, and
  licenses

Every EPUB passes EPUBCheck 5.3.0 and the local duplicate-ID, internal-link,
anchor, footnote-target, and cantillation checks. The pipeline's database,
presentation, and content-preservation tests also pass.

## Source limitations retained rather than invented

- Joshua 21:36-37 have Hebrew but no text in the approved English editions, so
  those two verses are Hebrew-only.
- 1,645 Sefaria link-index records point to commentary locations for which none
  of the approved selected exports contains text. Those stale/unresolvable
  pointers are reported in `build-report.json`; no text was fabricated.
- Eleven source verses contain bracketed qere-only or traditional repeated-line
  material. The bracketed reading is retained as source text without square
  brackets. All ordinary and multiword qere/ketiv pairs are rendered as pointed
  qere followed by bracketed ketiv.

Pending or unapproved commentary editions remain excluded. Targum and
unselected commentary groups are not included.

See `full-coverage.json`, `full-validation-results.json`,
`full-checksums.json`, `build-report.json`, and `source-selection.json` for the
machine-readable audit trail.
