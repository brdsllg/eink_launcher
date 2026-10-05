# How to rebuild the Tanach EPUBs

*For anyone who needs to refresh the book files. No coding experience required.*

The finished books live in `outputs/books/` as 39 EPUB files, one per book of the
Tanach. They are not written by hand; small programs *generate* them from a working
database. If anything changes (the text, the commentary, or even how a page looks),
the books must be generated again. That is a "rebuild". You only need to copy and
paste a few commands, in order.

## Before you start (once)

1. Open `C:\Users\levi\eink_launcher` in VS Code.
2. Open the terminal: **Terminal → New Terminal** (or press `` Ctrl+` ``).
3. Check Python by typing `python --version` and pressing Enter. You should see
   something like `Python 3.14.7`. If you see an error, Python must be installed first;
   ask for help.

Everything below is typed into that terminal and confirmed with Enter.

## Step 1: go to the Tanach folder

Always start here:

```powershell
cd C:\Users\levi\eink_launcher\tanach
```

## Step 2: rebuild (choose ONE)

**Only the appearance changed** (fonts, sizes, headings, layout, styling). This means
"redraw every book using the text we already have":

```powershell
python -X utf8 work/regenerate.py
```

**The text or commentary changed** (a verse, a translation, which commentaries are
included, the list of books). This means "refresh the database from the local source
files, then redraw every book". It does more work, so use it only when content
changed. **Not sure which? Use this one; it is always safe.** Neither command uses the
internet.

```powershell
python -X utf8 work/build.py
```

To try a single book first, without touching the other 38, run this, look at the
result, and only then run the full command (swap `Genesis` for any book name spelled
as in `outputs/source-selection.json`, such as `Obadiah`, `I Samuel`, or `Psalms`):

```powershell
python -X utf8 work/regenerate.py --book Genesis
```

Wait for a line such as `Generated 39 complete book EPUBs` and for the prompt to
return. The old files in `outputs/books/` are replaced in place. Some commands run for
a while without printing anything; that is normal.

## Step 3: check the new books

```powershell
python -X utf8 work/validate.py
```

This prints one line per book, such as `01-genesis.epub EPUBCheck exit 0`. **`exit 0`
means that book is fine.** Anything else, or a red error, means a book needs attention.
Do not skip this: Step 4 refuses to run until this check has passed.

## Step 4: refresh the shareable ZIP (optional)

Only needed if you want the single packaged file for the reader or another machine:

```powershell
python -X utf8 work/package_full.py
```

This updates `outputs/full-checksums.json`, rebuilds `outputs/tanach-39-epubs.zip`, and
refreshes its `.sha256`. It prints the new SHA-256 at the end; that is expected. To
refresh the sample-set ZIPs as well (separate and optional):

```powershell
python -X utf8 work/package_samples.py
```

## The whole routine in one block

The second command below is `build.py`, the safe choice. If only the appearance
changed, you can swap it for `regenerate.py`.

```powershell
cd C:\Users\levi\eink_launcher\tanach
python -X utf8 work/build.py
python -X utf8 work/validate.py
python -X utf8 work/package_full.py
```

## How do I know it worked?

- Each command ends with a summary line and returns to the normal prompt.
- Step 3 shows `exit 0` for all 39 books.
- File times in `outputs\books\` show today's date. To check from the terminal:

  ```powershell
  Get-ChildItem outputs\books\*.epub | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name, LastWriteTime
  ```

## If something goes wrong

| What you see | What it usually means | What to do |
|---|---|---|
| `python : not recognized` | Python isn't installed, or the terminal was opened before installing it | Install Python, then open a **new** terminal |
| `can't open file '...work/regenerate.py'` | Wrong folder | Redo Step 1, then retry |
| An error mentioning `source-selection.json` | The book/commentary list was changed in a way the programs can't read | Restore that file with git and ask for help before rebuilding |
| `Expected 39 EPUBs` | `outputs/books/` doesn't hold exactly 39 books | Don't delete files there by hand; ask for help |
| Validation prints something other than `exit 0` | One book was generated with a problem | Note which book it names and report it; the rest are fine |

Nothing in these steps deletes your source data. The worst case is running the rebuild
again.

## Two things not to do

- **Don't hand-edit files in `outputs\`.** They are generated, so the next rebuild
  silently overwrites your edit. A change belongs in the generator (`work/`) so it
  survives.
- **Don't run scripts in `work\legacy\`.** They are old one-off scripts kept for
  history, and some overwrite current settings.

## Short glossary

- **EPUB:** the book file format (one file per book).
- **Rebuild:** regenerate the book files from the working database.
- **Terminal:** the VS Code window where you type commands.
- **`work/cache`:** the local copy of the source texts; rebuilds read it, so they work
  offline.
- **`work/tanach.sqlite`:** the tidy database the generator draws from.

Technical detail: `docs/tanach/docs/tanach-epub.md` and
[`docs/tanach/README.md`](../README.md). The Talmud books have their own
guide: `docs/talmud/HOW-TO-SYNC.md`.
