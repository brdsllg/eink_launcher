# Tanach commentary whitelist

The 23 commentary groups included in the collection, the rules that govern them, and
what is excluded. This replaces the former checklist of about 130 candidates,
`selected-commentaries.md`, and `source-review.md`. The authoritative record, including
every candidate and edition decision, is `source-selection.json`.

## Rules

- **Direct commentary only:** each selected work's verse-addressed commentary plus
  explicit commentary links. No broad cross-citation links, whole essays, or "linked
  discussions". Direct supercommentary on Rashi attaches through its parent Rashi
  comment.
- **Full text** of every included comment, in Hebrew and available approved English;
  nothing is summarized.
- **A commentator whitelist and an attachment policy are separate controls.** Selecting
  a work (Rashi, say) selects all its book-specific entries together, not every English
  translation of it.
- **No Targum.** Pending and unapproved editions stay excluded.
- Religious approval and the availability of a particular exported edition are
  different questions. For example, Ramban is approved and already included; a separate
  "Ramban Commentary" export edition simply had no text.

## Selected groups

| ID | Commentary | ID | Commentary |
|---|---|---|---|
| C001 | Rashi | C014 | Or HaChaim |
| C002 | Ramban | C015 | Ba'al HaTurim |
| C003 | Ibn Ezra | C016 | Kitzur Ba'al HaTurim |
| C004 | Sforno | C017 | Kli Yakar |
| C005 | Rashbam | C019 | Chizkuni |
| C006 | Radak | C030 | Bartenura |
| C007 | Metzudat David | C035 | Chatam Sofer |
| C008 | Metzudat Zion | C061 | Jonathan Sacks (listed collections) |
| C009 | Malbim | C076 | Meiri |
| C011 | Ralbag | C083 | Mizrachi |
| C013 | Abarbanel | C098 | Rabbeinu Bahya |
| | | C116 | Siftei Chakhamim |

Or HaChaim and Siftei Chakhamim came from the explicitly named additions. Jonathan
Sacks stays eligible, but the direct-only rule excludes essays linked only by general
citations, and no qualifying notes were found for the sample passages; do not add
essay citations just to populate that source.

## Considered and not selected

The familiar-choice candidates left out were **Malbim Beur Hamilot** (C010), **Ralbag
Beur HaMilot** (C012), **Haamek Davar** (C018), and **Da'at Zekenim** (C020). All other
candidates, about 100 further works and collections (C021 to C133, minus those above),
are also excluded. Do not add Malbim Beur Hamilot or any unselected group separately.

## Where to find more

- Exact Sefaria titles behind each group: `source-selection.json`.
- Edition provenance queue: `../docs/tanach-epub.md`.
- How the commentary appears in the EPUBs: `reader-compatibility.md`.
