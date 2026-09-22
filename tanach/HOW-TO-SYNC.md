# How to keep the Tanach files safe and move them between computers

A plain-English guide. You do not need to know how to program to do any of this.

## The one idea

Your Tanach project contains two kinds of things:

1. **The recipe** — small (about 4 MB). The little scripts and the settings file that build the
   books. This is what GitHub is for.
2. **The books and heavy working files** — about 1.5 GB. The 39 finished EPUBs, the 9 samples,
   the ZIP downloads, the raw source cache, and the build database. These are personal-use
   reading material and far too big for GitHub.

So:

- **Recipe → GitHub.** "Commit" means "save a snapshot", "push" means "send it to GitHub".
- **Books → your own copy.** Move them with a USB stick, OneDrive, Google Drive, or a cable.

Why the books stay off GitHub: your GitHub project is **public**, meaning anyone on the
internet can read it. The book text comes from Sefaria with per-edition licences for personal
use, so it should not be published there.

## Action 1 — Save the recipe to GitHub (after any change to the pipeline)

In VS Code:

1. Click the branching icon in the left sidebar (Source Control), or press **Ctrl+Shift+G**.
2. Under "Changes" you will see a list: `.gitignore`, `tanach/README.md`, `tanach/work/...`
   (the scripts) and `tanach/outputs/source-selection.json`.
3. Click the **+** next to the word "Changes" to select everything in that list.
4. Type a short message in the box, for example: `tanach: keep pipeline in sync`
5. Click **Commit** (the ✓ button), then click **Sync Changes** (or **Push**).

Or type these three lines in the VS Code terminal (Ctrl+`) one after another:

```powershell
cd C:\Users\levi\eink_launcher
git add -A
git commit -m "tanach: keep pipeline in sync"
git push
```

Afterwards, this should print **nothing at all**. If it prints nothing, no book files were
uploaded — exactly what you want:

```powershell
cd C:\Users\levi\eink_launcher
git ls-files tanach | Select-String '\.epub$'
```

You do not need to worry that a book changed: git is told to ignore them, so they never slow
down a commit and can never be uploaded by accident.

## Action 2 — Put everything on your second computer

**Part A, the recipe (tiny).** First time only:

```powershell
cd C:\Users\levi
git clone https://github.com/brdsllg/eink_launcher.git
```

On later visits, just refresh it:

```powershell
cd C:\Users\levi\eink_launcher
git pull
```

**Part B, the books (no commands).**

1. Plug in a USB stick, or open OneDrive / Google Drive.
2. Copy this folder from the first computer: `C:\Users\levi\eink_launcher\tanach\outputs`
   (about 140 MB).
3. On the second computer, open `C:\Users\levi\eink_launcher\tanach\` and paste it there.
   You should end up with `...\tanach\outputs\books\01-genesis.epub` and so on.

**Optional** — only if you want that computer to rebuild books without downloading anything
again (about 1.4 GB): copy `tanach\work\cache` and the single file `tanach\work\tanach.sqlite`
the same way.

To actually *run* the pipeline on the second computer it needs Python 3.11 or newer
from python.org. Reading the books on the tablet does not need Python.

## Action 3 — Put the books on the Bigme reader

Easiest way, no commands: plug the tablet in with the USB cable, open
`C:\Users\levi\eink_launcher\tanach\outputs\books` in File Explorer, and drag the EPUB files
into the tablet's `Download` folder.

If you prefer the command line:

```powershell
cd C:\Users\levi\eink_launcher
adb push tanach\outputs\books\. /sdcard/Download/Tanach/
```

## Things to never do

- Never run `git add -f` (the `-f` forces files in, including the books).
- Never drag an EPUB or ZIP into the GitHub website.
- Never commit the 70 MB ZIP files.

## If you would rather the books synced with git too

That is possible, but the GitHub project must be **private** first (Settings → General →
scroll to "Danger Zone" → Change visibility → Private), because of the personal-use licences.
Once it is private, ask the assistant to set up "Git LFS": the books would then travel with
`git clone` and `git push` like the recipe does. Keep in mind GitHub's free allowance:
1 GB stored and 1 GB downloaded per month, and each rebuild re-uploads about 70 MB.
