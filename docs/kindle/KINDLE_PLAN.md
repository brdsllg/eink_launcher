# Moving the app to the Kindle Paperwhite (11th generation)

Research and plan, written 4 Nov 2026. Nothing here has been built or tried on the
Kindle yet. Whether something works on the device is recorded only in the issue
tracker in [DEVICE_TESTING.md](../DEVICE_TESTING.md) (new Kindle items will get their
own IDs there, prefix `KND-`).

## Why the app cannot just be copied over

The app is Flutter/Dart for **Android**. The Kindle runs its own Linux system with no
Android, so none of `lib/` can run there. What carries over is not the code but:

1. The **content pipeline** (`tanach/`, `talmud/`): Sefaria to EPUB, plus the study
   sidecars. It is Python and independent of the app.
2. The **dictionary data** (WordNet, modern Hebrew, Jastrow) and the build tools'
   knowledge of where it comes from.
3. The **feature list and the decisions already made** (this document uses them).

## Device facts (what the new code has to live with)

- Kindle Paperwhite 11th generation (2021): 6.8 inch, 300 ppi, about 1236 x 1648,
  MediaTek 1 GHz class chip, **512 MB RAM**. Touch only, no page buttons, no SD card.
- Jailbroken with SpiderCat (works on firmware 5.16.3 to 5.19.5; it is patched in
  5.19.6, so keep the Kindle from updating itself). SpiderCat installs KPM, which
  installs KOReader and other homebrew.
- Reported: firmware 5.19.3 and newer removed the Java layer the classic KUAL used.
  A native launcher called KUAL Next exists for those firmwares. Check which launcher
  your install actually shows before relying on KUAL menus.
- The Kindle is a normal Linux device: a program can be started from a script,
  can draw to the framebuffer and read touch events. That is what makes a standalone
  app possible, and also why it is a lot of work (see Path B).

## Every feature, and where it goes on the Kindle

"Built in" means KOReader already does it, so no code is needed.

| App feature | On the Kindle | Work |
| --- | --- | --- |
| File browser: browse, search, create, rename, copy, move, delete | KOReader file manager | Built in |
| Recycle bin (30-day auto clear) | Plugin that moves deleted files into a hidden bin folder and purges old ones | Small plugin |
| Home screen / launcher, battery, clock | KOReader file manager and status bar; KOReader autolaunch extension to open it at boot | Built in + one extension |
| App drawer | KUAL / KUAL Next lists extensions | Built in (optional later: a KOReader page listing them) |
| Screen edges (cracked panel) | Not needed on this screen | Dropped |
| Startup recovery, memory-pressure observers, diagnostics | KOReader has its own crash handling | Dropped |
| Physical page buttons | The Kindle has none | Dropped |
| PDF reading: fit height, fit width, zoom/scroll, crop, overlap | KOReader PDF engine (fit, zoom, panning, crop, reflow) | Built in |
| PDF image dithering, grayscale | KOReader contrast and dithering options | Built in |
| EPUB, TXT, Markdown reading, fonts, size, line height, margins, justification, hyphenation | KOReader's EPUB engine; copy the bundled fonts (Literata, Frank Ruhl Libre, Noto Serif Hebrew, Heebo) into KOReader's fonts folder | Built in + copy fonts |
| Hebrew and mixed-direction text | KOReader engine; font choice matters (see HEB-001) | Built in + test |
| Tap zones, swipes, rotation | KOReader gestures | Built in |
| Per-document position and settings | KOReader keeps a sidecar per book | Built in |
| Bookmarks, contents, go to page | Built in | Built in |
| Text search (EPUB/TXT/MD) | KOReader full-text search; Hebrew mark-insensitive search must be tested | Built in + test |
| Select text: copy, dictionary, note, underline, multi-paragraph | KOReader highlights, notes (underline style available), selection across paragraphs and pages | Built in |
| Tabs (several open books) | Not in KOReader. Plugin keeps a list of open books and switches by reopening (position restores from the sidecar) | Medium plugin |
| Offline dictionaries (English, modern Hebrew, Rabbinic Hebrew and Aramaic) | KOReader uses StarDict dictionaries; convert our three data sets to StarDict. Hebrew lookups must ignore vowel marks (a small plugin hook or alias entries) | Converter tool + small hook |
| Study books: translation picker | Plugin plus a Kindle-friendly EPUB layout (below) | Main plugin |
| Study books: commentary picker, per-source, Hebrew/English/both, source order | Same plugin | Main plugin |
| Study books: hide vowel points (Talmud) | Open decision (below) | Decision needed |
| Torah parsha and aliyah headings, Tehillim 30-day headings | Plugin navigation lists built from the same tables the builder already has | Small, inside the main plugin |
| Fast study search over the SQLite sidecar | KOReader ships SQLite for plugins, so the existing `.study.sqlite` idea carries over | Inside the main plugin |

## The two paths

### Path A: KOReader plugins plus Kindle-ready books (recommended)

Write the missing pieces as KOReader plugins in Lua (each is a folder ending in
`.koplugin` with `_meta.lua` and `main.lua`). Change the book builders so they also
produce a version laid out for KOReader.

How the study books would work:

- The builder writes commentary **inline**, each comment wrapped with its source name
  as an attribute. The plugin picks sources, language and translation, and applies
  them as a per-book style rule (`display: none` on everything not chosen). KOReader's
  engine understands attribute selectors and book-specific styles, so no repagination
  code is needed.
- Verse and daf navigation, parsha/aliyah/Tehillim lists, and the search box are
  plugin screens that jump to anchors in the book.
- Heavy data (search index) stays in SQLite, read from Lua.

### Path B: a brand-new standalone Kindle app

A native program (for example Rust or C with a framebuffer library; one developer has
shown Rust with the Slint toolkit drawing on a jailbroken Paperwhite 7th gen and
reading touch input, but only as a counter demo). It would have to supply, from
scratch: PDF rendering, EPUB layout, Hebrew shaping and bidi, hyphenation, e-ink
refresh handling, touch gestures, text selection, annotations, dictionaries, file
management, power and Wi-Fi handling, and then the study features on top.

### Side by side

| | Path A: KOReader plugins | Path B: new app |
| --- | --- | --- |
| Features that already exist for free | Almost all of the reader and launcher | None |
| New code to write | A study plugin, tabs, recycle bin, dictionary converter, a builder option | Everything |
| Open problems it inherits | Few; selection, PDF and big-book handling are mature | All the problems this project has already fought: selection handles (SEL-003 to SEL-023), freezes on huge paragraphs (TAL-015), PDF scheduling and memory |
| Hebrew rendering | Proven engine; font and mark placement still need a test | Must be built and tuned |
| 512 MB RAM | KOReader is designed for this class of device | Your risk to manage |
| Testing loop | KOReader runs on a PC, so plugins can be tried on the ThinkPad before copying to the Kindle | Cross-compile, copy, run on the Kindle every time |
| Fits an AI-assisted, non-coder workflow | Yes: small Lua files, one feature at a time | Poor: large native code with no quick way to check it |
| Survives firmware changes | Same exposure as KOReader itself | Same exposure, plus your own display and input code |
| Time to first useful result | Days | Many months |
| Biggest risk | Plugin hooks may not reach everything wanted (fallback: patch KOReader itself) | Never reaching parity with what KOReader already does |
| Downside | KOReader's own screens look different until they are replaced (see "Making it look like the app") | Full control of every pixel |

### Verdict

**Path A.** Path B only wins if KOReader cannot open the study books at an acceptable
speed. That is a measurable question, and Path A starts by answering it, so nothing is
lost by trying A first. If the plugin hooks turn out to be too limited, the fallback
is to patch KOReader's own code (still Path A's engine), not to start from zero.

## Making it look like the app (added 4 Nov 2026)

The owner likes the app's look and dislikes KOReader's. That does not change the
verdict, because KOReader is built in two layers:

- **Engine and system layer (keep):** EPUB and PDF rendering, e-ink refresh, touch
  input, power and Wi-Fi handling, caches, per-book sidecar files, crash handling.
- **Lua front end (replace what is visible):** every screen, menu and dialog, plus the
  logic for selection, notes, bookmarks, contents and search. It is plain Lua source
  drawn by KOReader's own toolkit (no native widgets), so any layout is possible,
  including the app's grid of rectangular cells, permanent rules and inverted pressed
  state (see [LAYOUT_DESIGN.md](../LAYOUT_DESIGN.md)).

Depth options, shallowest first:

1. **Skin with user patches** (Lua files in `koreader/patches/`, run at startup).
   Community patches already restyle the title bar, add bottom tab bars and quick
   settings; the ZenOS plugin replaces the launcher, status bars and menus. Survives
   KOReader updates best, but only bends the screens that already exist.
2. **Replace the screens with our own (the plan):** one UI plugin plus patches that
   draw the app's file browser, reader menu, tab strip, contents, bookmarks, search,
   settings and dialogs, calling KOReader's logic underneath. Unwanted plugins and
   menu entries are switched off. Pin one KOReader version so patches do not break.
3. **Fork the Lua front end:** edit KOReader's Lua files directly. Most control, but
   every KOReader update then has to be merged by hand. Only if 2 hits a wall.
4. **Not practical:** use only the engine libraries (crengine, MuPDF) with a front
   end in another language. Selection, notes and bookmarks live in the Lua front end,
   so they would have to be rebuilt; this is Path B in disguise.

Known difference in feel: as far as I know KOReader selects text by long-press and
drag, not with two draggable handles like the app (SEL-001 to SEL-005). Handles can be
built on top of KOReader's selection functions, but that is its own piece of work.

First step: a one-screen spike. Build the file browser with the app's layout as a
plugin, look at it on the PC build of KOReader, then on the Kindle. If it looks right,
the other screens follow the same pattern.

## Plan

**Phase 0: no code, one evening.** Install KOReader through KPM, copy Berakhot, Tamid
and one Tanach book (for example Ruth) as they are, copy the fonts, and open them.
Record: first open time, page-turn speed, whether Hebrew vowels and the meteg look
right, and whether the chapter-end notes behave sensibly. This is the go/no-go for
how much the books must change.

**Phase 1: study plugin and Kindle-layout books.** Builder option that writes inline,
source-tagged commentary; plugin with translation, commentary, language, and source
order controls; verse/daf/parsha/aliyah/Tehillim navigation.

**Phase 2: tabs and recycle bin.**

**Phase 3: dictionaries and search.** StarDict versions of the three dictionaries,
vowel-insensitive Hebrew lookup, vowel-insensitive study search from the sidecar.

**Phase 4 (optional):** app drawer page, daily Tehillim shortcut, fonts and style
presets.

Folder plan inside this repository: `kindle/koreader-plugins/<name>.koplugin/` for the
plugins, `kindle/tools/` for the dictionary and book converters.

## Open decisions for Levi

1. **Hide vowel points (Talmud).** CSS cannot strip marks. Choices: (a) the builder
   writes a pointed and an unpointed copy of each tractate and the plugin switches
   between them (double the storage), (b) a plugin that rewrites the text of the open
   chapter on demand, (c) drop the setting on the Kindle.
2. **Inline commentary size.** Genesis 1 alone is about 3 MB of XHTML with every
   commentary on. Phase 0 shows whether KOReader copes; if not, the builder can write
   one file per source, or only the sources actually wanted per book.
3. **Tabs.** Switching reopens a book, which takes a moment on this hardware. Is that
   acceptable, or is a simple "recent books" list enough?

## What was found, and where

- SpiderCat release and supported firmware: kindlemodding.org (SpiderCat page),
  The eBook Reader Blog (1 Sep 2026), TerminalBytes.
- Paperwhite 11th gen specs: Good e-Reader, iFixit, comparison tables.
- KOReader plugin layout and SQLite access: KOReader development guide and
  `doc/DataStore.md`; example plugins (calibre, statistics, kotranslate).
- KOReader dictionaries, book-specific CSS tweaks, autolaunch extension: KOReader
  wiki (Dictionary support), KOReader issues and releases, KUAL extension listing.
- KUAL and Java removal in 5.19.3+: MobileRead (KUAL Next thread).
- Native app feasibility: sverre.me (Rust and Slint on a Kindle), kapps.
- Features of this app: `docs/README.md`, `docs/READER_PLAN.md`,
  `docs/PLANNED_FEATURES_STATUS.md`, `lib/reader/models/reader_settings.dart`,
  `lib/reader/models/tehillim_daily.dart`, `tool/`.
