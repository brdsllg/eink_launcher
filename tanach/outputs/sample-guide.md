# Tanach EPUB sample set

Nine chapter samples for testing on the Bigme B751C and your existing reader. These are not the complete 39 books.

## Your settings

- Metsudah beneath the Hebrew where available, with Koren as the fallback.
- Other approved English translations are available through each verse’s notes link.
- Hebrew has vowels and no cantillation. Qere appears in the main text; ketiv follows in brackets. Divine names retain the source spelling.
- Full text from the user’s 23 whitelisted commentary groups, in Hebrew and selected English editions where available. Direct commentary only; no broad cross-citations or expanded essays. No Targum.
- The exact whitelist is recorded in selected-commentaries.md. Jonathan Sacks is eligible, but general essay/citation links are excluded by the direct-only policy.
- Source credits appear only at the end. Verses have a compact bold heading on one row: English left, Hebrew right. Commentary is grouped by source and verse, retaining separate comment paragraphs. Verse and commentary text use equal sizes, without indentation.
- Chapter-only navigation and left-to-right page progression; Hebrew text remains RTL. Sources and edition licenses remain in the final spine page without cluttering the table of contents.

## Samples

| Chapter | Verses | Commentary notes in this book | Sources | Default translation | EPUB size |
|---|---:|---:|---:|---|---:|
| Genesis 1 | 31 | 1,063 | 19 | Metsudah | 0.79 MB |
| Deuteronomy 32 | 52 | 1,400 | 17 | Metsudah | 0.57 MB |
| I Samuel 17 | 58 | 325 | 7 | Metsudah | 0.09 MB |
| Isaiah 40 | 31 | 421 | 7 | Koren | 0.09 MB |
| Jonah 1 | 16 | 190 | 7 | Koren | 0.05 MB |
| Psalms 23 | 6 | 70 | 7 | Koren | 0.02 MB |
| Job 1 | 22 | 199 | 7 | Koren | 0.05 MB |
| Ruth 3 | 18 | 69 | 4 | Metsudah | 0.03 MB |
| Daniel 2 | 49 | 410 | 5 | Koren | 0.08 MB |

There are 4,147 distinct commentary notes across the samples. Included comments retain their full text. Attachments use explicit chapter/verse structure (including selected supercommentary) or Sefaria links typed commentary. Broad citation links and whole-essay expansion are excluded. A verse-level link opens the source list, then an individual note opens the full text.

## Validation

- All nine EPUBs passed EPUBCheck 5.3.0.
- Every local file link and anchor was checked; all note references resolve to footnote asides. No duplicate IDs or remaining cantillation in base-text paragraphs.
- Automated checks cover translation fallback, qere/ketiv including read-only and written-only words, ranges, reference sorting, source-markup handling, and database relationships.
- Browser previews were checked at 800 × 1280. This does not establish compatibility or performance in the Bigme reader.

## What to try on the device

Start with Ruth 3 for qere/ketiv and Metsudah, Isaiah 40 for Koren fallback, and Genesis 1 for a heavy commentary chapter. Open a verse’s notes list, select a note, and return to the verse. Check Hebrew vowel placement, bracket direction, chapter loading time, and whether your reader supports links inside footnotes.

Genesis 1 and Deuteronomy 32 remain useful loading tests because the selected direct commentaries can be substantial.

## Coverage limits

- 1645 candidate export links remain unattached; detailed references and reasons are in build-report.json. Some point to unavailable editions, excluded translations, or commentary outside this sample’s download scope. Some refer to segments absent or numbered differently in the selected editions; available direct verse commentaries are still attached independently.
- Selecting a source does not guarantee a note on every sample verse. Only material present in the selected exports and attached under the direct-only policy is included.
- Some source files report their license as “unknown”; the colophons retain that exact label rather than inventing one.
- Commentary translations with uncertain provenance are withheld below. The original Hebrew remains included when available.

## Commentary edition metadata to investigate

This is an internal edition-review queue, not a list of commentators whose Orthodox status is in doubt. The earlier request for a blanket decision was premature: generic edition labels need metadata and content checks first. These English edition variants are withheld for now; the named commentators can already be included through other editions. Only a specific unresolved religious or editorial choice should be referred back to the user.

Ramban is approved and already included: the Genesis and Deuteronomy samples contain Hebrew and English Ramban. The additional edition labeled “Ramban Commentary” links to Judaica Press but contains no exported text. It has been removed from this review queue; no user decision is needed for it.

| Edition | Commentary works affected |
|---|---|
| Abrabanel on 1522 | Abarbanel on Torah |
| Artscroll Series | Ramban on Exodus |
| Chronicles, English translation by I.W. Slotki, Soncino Press, 1952 | Radak on I Chronicles |
| Commentary of Ibn Ezra on Isaiah - trans. by M. Friedlander, 1873 | Ibn Ezra on Isaiah |
| Corrected Rashi English  | Rashi on Genesis |
| Ibn Ezra on Exudus -- Commetator's Bible  | Ibn Ezra on Exodus |
| Ibn Ezra on Proverbs -- Daat | Ibn Ezra on Proverbs |
| Ibn Ezra on the Pentateuch - trans. by Jay F. Shachter | Ibn Ezra on Leviticus |
| Ibn Ezra on the Pentateuch; trans. by Jay F. Shachter | Ibn Ezra on Deuteronomy |
| JPS Miqra'ot Gedolot | Ramban on Leviticus |
| Kitzur Baal HaTurim | Kitzur Ba'al HaTurim on Genesis |
| Malbim's Job, trans. Jeremy I. Pfeffer. Ktav, 2003 | Malbim on Job |
| Matan | Malbim on I Samuel, Radak on Judges |
| McCaul Translation | Radak on Zechariah |
| Nehama Leibowitz | Ramban on Genesis |
| Numbers 291 Ibn Ezra | Ibn Ezra on Numbers |
| R. David Kimhi on the first book of Psalms, Translated by R.G. Finch, London, 1919 | Radak on Psalms |
| Rabbi Moses ben Nahman Nahmanides, 13th C. Spain, Commentary on Exodus 1718 | Ramban on Exodus |
| Ramban Numbers 2018 | Ramban on Numbers |
| Rashi Jeremiah 112 | Rashi on Jeremiah |
| Sefaria Community Translation | Abarbanel on Amos, Abarbanel on Ezekiel, Abarbanel on Hosea, Abarbanel on I Kings, Abarbanel on I Samuel, Abarbanel on II Kings, Abarbanel on II Samuel, Abarbanel on Isaiah, Abarbanel on Jeremiah, Abarbanel on Joel, Abarbanel on Jonah, Abarbanel on Joshua, Abarbanel on Judges, Abarbanel on Obadiah, Abarbanel on Torah, Abarbanel on Zechariah, Ba'al HaTurim on Genesis, Bartenura on Torah, Chatam Sofer on Torah, Chizkuni, Ibn Ezra on Daniel, Ibn Ezra on Deuteronomy, Ibn Ezra on Ecclesiastes, Ibn Ezra on Esther, Ibn Ezra on Exodus, Ibn Ezra on Genesis, Ibn Ezra on Hosea, Ibn Ezra on Isaiah, Ibn Ezra on Joel, Ibn Ezra on Jonah, Ibn Ezra on Lamentations, Ibn Ezra on Leviticus, Ibn Ezra on Malachi, Ibn Ezra on Nahum, Ibn Ezra on Nehemiah, Ibn Ezra on Numbers, Ibn Ezra on Proverbs, Ibn Ezra on Psalms, Ibn Ezra on Ruth, Ibn Ezra on Zechariah, Kitzur Ba'al HaTurim on Deuteronomy, Kitzur Ba'al HaTurim on Exodus, Kitzur Ba'al HaTurim on Genesis, Kitzur Ba'al HaTurim on Leviticus, Kitzur Ba'al HaTurim on Numbers, Kli Yakar on Deuteronomy, Kli Yakar on Exodus, Kli Yakar on Genesis, Kli Yakar on Leviticus, Kli Yakar on Numbers, Malbim on Daniel, Malbim on Deuteronomy, Malbim on Esther, Malbim on Exodus, Malbim on Ezekiel, Malbim on Genesis, Malbim on I Chronicles, Malbim on I Kings, Malbim on I Samuel, Malbim on II Kings, Malbim on II Samuel, Malbim on Isaiah, Malbim on Jeremiah, Malbim on Jonah, Malbim on Joshua, Malbim on Judges, Malbim on Leviticus, Malbim on Malachi, Malbim on Micah, Malbim on Numbers, Malbim on Proverbs, Malbim on Psalms, Malbim on Ruth, Malbim on Zechariah, Metzudat David on Ecclesiastes, Metzudat David on Ezekiel, Metzudat David on Hosea, Metzudat David on I Kings, Metzudat David on I Samuel, Metzudat David on II Kings, Metzudat David on II Samuel, Metzudat David on Isaiah, Metzudat David on Jeremiah, Metzudat David on Jonah, Metzudat David on Joshua, Metzudat David on Judges, Metzudat David on Nehemiah, Metzudat David on Obadiah, Metzudat David on Proverbs, Metzudat David on Psalms, Metzudat David on Song of Songs, Metzudat Zion on Ecclesiastes, Metzudat Zion on I Kings, Metzudat Zion on II Kings, Metzudat Zion on Joshua, Metzudat Zion on Judges, Metzudat Zion on Malachi, Metzudat Zion on Psalms, Metzudat Zion on Zechariah, Mizrachi, Or HaChaim on Deuteronomy, Or HaChaim on Exodus, Or HaChaim on Genesis, Or HaChaim on Leviticus, Or HaChaim on Numbers, Rabbeinu Bahya, Radak on Amos, Radak on Ezekiel, Radak on Genesis, Radak on I Chronicles, Radak on I Kings, Radak on I Samuel, Radak on II Kings, Radak on II Samuel, Radak on Isaiah, Radak on Jeremiah, Radak on Jonah, Radak on Joshua, Radak on Judges, Radak on Malachi, Radak on Psalms, Radak on Zechariah, Ralbag Ruth, Ralbag on I Kings, Ralbag on I Samuel, Ralbag on II Kings, Ralbag on II Samuel, Ralbag on Joshua, Ralbag on Judges, Ralbag on Nehemiah, Ralbag on Proverbs, Ralbag on Song of Songs, Ralbag on Torah, Ramban on Deuteronomy, Ramban on Exodus, Ramban on Genesis, Ramban on Job, Ramban on Leviticus, Ramban on Numbers, Rashbam on Deuteronomy, Rashbam on Exodus, Rashbam on Genesis, Rashbam on Leviticus, Rashbam on Numbers, Rashi on Amos, Rashi on Daniel, Rashi on Deuteronomy, Rashi on Ecclesiastes, Rashi on Esther, Rashi on Exodus, Rashi on Ezekiel, Rashi on Ezra, Rashi on Genesis, Rashi on Haggai, Rashi on Hosea, Rashi on I Kings, Rashi on I Samuel, Rashi on II Chronicles, Rashi on II Kings, Rashi on II Samuel, Rashi on Isaiah, Rashi on Jeremiah, Rashi on Job, Rashi on Joel, Rashi on Jonah, Rashi on Joshua, Rashi on Judges, Rashi on Lamentations, Rashi on Leviticus, Rashi on Malachi, Rashi on Nahum, Rashi on Numbers, Rashi on Proverbs, Rashi on Psalms, Rashi on Ruth, Rashi on Song of Songs, Rashi on Zechariah, Rashi on Zephaniah, Sforno on Deuteronomy, Sforno on Exodus, Sforno on Genesis, Sforno on Leviticus, Sforno on Numbers, Siftei Chakhamim |
| Sefaria Edition | Rashi on Genesis |
| Sefaria Kli Yakar, 2026 Claude 3.7, ed. Francis Nataf ✧ | Kli Yakar on Deuteronomy, Kli Yakar on Exodus, Kli Yakar on Genesis, Kli Yakar on Leviticus, Kli Yakar on Numbers |
| The Biblical Exegesis of Don Isaac Abrabanel. PhD thesis by Dr. David E. Cohen, University of London, 2015 | Abarbanel on I Samuel, Abarbanel on Torah |
| The Commentary of Radak to Chronicles A Translation with Introduction and Supercommentary, by Yitzhak Berger, Brown University, 2007 | Radak on I Chronicles, Radak on II Chronicles |
| The Commentators Bible Leviticus THe Rubin JPS Miqra'ot Gedolot | Ramban on Leviticus |
| Trans. Betzalel Avraham Feinstein, 2026 | Malbim on Amos, Malbim on Daniel, Malbim on Ezra, Malbim on Habakkuk, Malbim on Haggai, Malbim on Joel, Malbim on Jonah, Malbim on Judges, Malbim on Malachi, Malbim on Nahum, Malbim on Nehemiah, Malbim on Obadiah, Malbim on Ruth, Malbim on Song of Songs, Malbim on Zechariah, Malbim on Zephaniah |
| Wikisource | Sforno on Genesis |
| Wikisource Mikraot Gedolot | Ibn Ezra on Psalms, Rashi on Genesis, Rashi on Psalms |
| ralbag on I Kings 723 | Ralbag on I Kings |
| לב שמח ייטיב פנים english | Malbim on Proverbs |

## Reader integration

The detailed implementation contract, actual XHTML examples, cache rules, and device test matrix are in reader-compatibility.md.

- Base verses: `section.verse`, stable `id="v-{book}-{chapter}-{verse}"`, and `data-ref`.
- The verse-level noteref opens an index aside with `data-category="index"`. A custom reader can skip this index and use its contained source-specific noterefs directly.
- Full commentary: grouped `aside epub:type="footnote"` entries use generated `g-…` anchors plus `data-source`, `data-category` (`rishon`, `acharon`, `modern`), and verse-level `data-ref`.
- Alternate translations use `data-category="translation"` and edition identifiers.
- Hebrew and English commentary blocks have explicit language and direction attributes; edition IDs preserve provenance.
- Each `.comment-segment` keeps its original `data-note-id` and may appear in more than one verse group when the source attaches it to multiple verses; group-level backlinks return to the invoking verse.
- EPUB files require no scripts or network connection. Fonts are left to the reader; no proprietary font is embedded.

The SQLite database and original cached files remain in the workspace for further development. The pipeline archive contains the scripts and selection manifest, not the large cache or Java tools.
