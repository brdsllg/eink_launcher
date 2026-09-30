# How to rebuild the Tanach EPUBs

*For anyone who needs to refresh the book files — no coding experience required.*

This project keeps the finished books in `outputs/books/` as 39 separate EPUB files
(one per book of the Tanach). Those files are **not** written by hand: they are
*generated* from a working database by small programs. So if anything about them
changes — the text, the commentary, or just the way a page looks — the books have to
be generated again. That is what "rebuild" means.

You do not need to understand the programs. You only need to copy and paste a few
commands, in the right order.

---

## Before you start (once)

1. Open the project folder `C:\Users\levi\eink_launcher` in VS Code.
2. Open the built-in terminal: **Terminal → New Terminal** (or press `` Ctrl+` ``).
3. Check that Python is installed by typing this and pressing Enter:

   ```powershell
   python --version
   ```

   You should see something like `Python 3.14.7`. If you instead see an error,
   Python needs to be installed before you continue — ask for help.

Everything below is typed into that terminal window, then confirmed with Enter.

---

## Step 1 — Move into the Tanach folder

Always start here. This one line puts you in the right place:

```powershell
cd C:\Users\levi\eink_launcher\tanach
```

---

## Step 2 — Rebuild the books (choose ONE of these two)

There are two rebuild commands and they do different amounts of work. Pick the one
that matches what changed.

### If only the **appearance** changed (fonts, sizes, headings, layout, styling)

```powershell
python -X utf8 work/regenerate.py
```

Plain English: "Redraw every book using the text we already have."

### If the **text or commentary** changed (a verse, a translation, which
commentaries are included, the list of books)

```powershell
python -X utf8 work/build.py
```

Plain English: "Go back to the local source files, refresh the database, then redraw
every book." This one does more work than `regenerate.py`, so use it only when the
actual content changed. **Not sure which one to use? Use this one — it is always
safe.** Neither command uses the internet.

> Want to test a single book first, without touching the other 38? Run this, look at
> the result, and only then run the full command:
>
> ```powershell
> python -X utf8 work/regenerate.py --book Genesis
> ```
>
> Swap `Genesis` for any book name, spelled exactly as in the list inside
> `outputs/source-selection.json` (for example `Obadiah`, `I Samuel`, `Psalms`).

Wait for it to print a line such as `Generated 39 complete book EPUBs` and for the
prompt to come back. The old files in `outputs/books/` are replaced in place.

---

## Step 3 — Check the new books are valid

```powershell
python -X utf8 work/validate.py
```

This inspects all 39 books and prints a line for each one, e.g.
`01-genesis.epub EPUBCheck exit 0`. **`exit 0` means that book is fine.** Anything
other than `0`, or a red error message, means a book needs attention.

Do not skip this step — Step 4 refuses to run until this check has passed.

---

## Step 4 — Refresh the shareable ZIP file (optional)

Only needed if you want the single packaged file that is handed to the reader or
copied to another machine:

```powershell
python -X utf8 work/package_full.py
```

This updates `outputs/full-checksums.json` (a list of fingerprints for the books),
rebuilds `outputs/tanach-39-epubs.zip`, and refreshes
`outputs/tanach-39-epubs.zip.sha256`. It prints the new SHA-256 value at the end —
that line is expected, not an error.

If you also want the sample-set ZIPs refreshed, that is a separate optional command:

```powershell
python -X utf8 work/package_samples.py
```

---

## The whole routine, in one copy-paste block

Change the second line to `build.py` if the *content* changed rather than just the
appearance:

```powershell
cd C:\Users\levi\eink_launcher\tanach
python -X utf8 work/build.py
python -X utf8 work/validate.py
python -X utf8 work/package_full.py
```

---

## How do I know it worked?

- Each command ends by printing a summary line and returns you to the normal prompt
  (no `>>>` and no hanging). Occasionally a command runs for a while with no output —
  that is normal; let it finish.
- Step 3 shows `exit 0` for all 39 books.
- The timestamps on the files in `outputs\books\` are now today's date. You can see
  this in File Explorer, or ask the terminal:

  ```powershell
  Get-ChildItem outputs\books\*.epub | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name, LastWriteTime
  ```

---

## If something goes wrong

| What you see | What it usually means | What to do |
|---|---|---|
| `python : not recognized` | Python is not installed, or the terminal was opened before installing it | Install Python, then open a **new** terminal |
| `can't open file '...work/regenerate.py'` | You are in the wrong folder | Redo Step 1 (`cd ...\tanach`), then retry |
| An error mentioning `source-selection.json` | A change was made to the book/commentary list that the programs cannot read | Restore that file with git and ask for help before rebuilding |
| `Expected 39 EPUBs` | `outputs/books/` does not hold exactly 39 books | Do not delete files there by hand; ask for help |
| Validation prints something other than `exit 0` | One book was generated with a problem | Note which book it names and report it; the rest are fine |

Nothing in these steps deletes your source data. The worst case is that a rebuild has
to be run again.

---

## Two things not to do

- **Do not hand-edit files inside `outputs\`.** They are generated, so the next
  rebuild will silently overwrite your edit. If a change is needed, it belongs in the
  generator (`work/`) so that it survives the rebuild.
- **Do not run scripts in `work\legacy\`.** Those are old one-off scripts kept for
  history. Some of them overwrite current settings. See `work\legacy\README.md`.

---

## Short glossary

- **EPUB** — the book file format (one file per book).
- **Rebuild** — re-generate the book files from the working database.
- **Terminal** — the window in VS Code where you type the commands.
- **`work/cache`** — the local copy of the source texts; a rebuild reads these, so it
  works offline.
- **`work/tanach.sqlite`** — the tidy database the generator draws from.

For the full technical detail behind these steps, see `docs/tanach-epub.md` and
`outputs/pipeline-readme.md`.

