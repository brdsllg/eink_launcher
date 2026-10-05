# Historical one-off scripts

Past migrations that reshaped the sample-era EPUBs into the revision 5
grouped-commentary presentation. They are **not** part of the build; they are kept only
as a record. **Do not rerun them:** several overwrite current preferences, duplicate
edits, or patch documents that have moved on.

Make future changes directly in `work/build.py` (presentation),
`outputs/source-selection.json` (configuration), and the relevant document.

| File | What it did once |
|---|---|
| `apply_whitelist.py` | Applied the approved commentary whitelist to the sample build |
| `document_grouped_format.py` | Documented the grouped-commentary format in the reader guide |
| `refine_presentation.py` | Presentation refinements before revision 5 |
| `revise_grouped_notes.py` | Rewrote commentary asides into source/verse groups |
| `revise_heading_blocks.py` | Rewrote verse headings into the one-row bilingual heading |
| `update_heading_presentation.py` | Heading and translation-label cleanup |
| `previous-sample-coverage.json` | Obsolete sample coverage snapshot (reference only) |

They were written to run from `work/` (several import from `sync` or use relative
paths). To inspect or reuse one, copy it into `work/` first and leave the original here.
