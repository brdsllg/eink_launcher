# Historical one-shot scripts

These scripts are not part of the current build sequence. They were the one-shot migrations
that reshaped the sample-era EPUBs into the revision-5 grouped-commentary presentation, and
they are kept only as provenance.

Do not rerun them blindly: several overwrite current preferences, duplicate edits, or patch
documents that have moved on. Make presentation changes in `work/build.py`, configuration
changes in `outputs/source-selection.json`, and documentation changes in the relevant file.

| File | Original one-shot purpose |
|---|---|
| `apply_whitelist.py` | Applied the approved commentary whitelist to the sample build. |
| `document_grouped_format.py` | Documented the grouped-commentary format in the reader contract. |
| `refine_presentation.py` | Presentation refinements before revision 5. |
| `revise_grouped_notes.py` | Rewrote commentary asides into source/verse groups. |
| `revise_heading_blocks.py` | Rewrote verse headings into the single-row bilingual heading. |
| `update_heading_presentation.py` | Heading and translation-label cleanup pass. |
| `previous-sample-coverage.json` | Obsolete sample coverage snapshot, now only a historical reference. |

They were written to run from `work/` (several do `from sync import ...` or use relative
paths). To inspect or reuse one, copy it back into `work/` first; leave the originals here.
