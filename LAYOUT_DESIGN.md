# Layout decisions for the 1.0.8 trial

The app shares rectangular cells, permanent rules, restrained spacing, and clear
selected/disabled states. Each area chooses its own columns. Dimensions below
are Flutter logical pixels; flexible tracks receive the remaining width.

| Area | Implemented layout | Why this choice |
| --- | --- | --- |
| Reader status and PDF modes | Battery, clock, page count, percentage, Contents, Settings use **1:2:3:1:1:1**. Modes use **1:1:1**. | This is the one place where ninths are useful: the page-count cell aligns exactly with the middle third, as requested. |
| Reader title bar | Home and Bookmarks each **56px**, flexible title, **96px rotation**. Below 360px, icons become 48px and rotation 88px. Text search gets another icon cell. | Rotation has a word and an icon, so it needs more room. Fixed side tracks keep targets usable on a phone and give extra landscape width to the book title. Equal fractions made the rotation label too small and wasted wide-screen space on simple icons. |
| Reader tabs | **56px arrows** (48px on narrow screens); three **equal** tabs divide the remainder. Each close target remains 40px. | All books retain equal visual weight. Equal arrows and fixed close targets leave as much space as possible for titles without making arrows enormous in landscape. |
| Browser header | Home 48px, clock 72px, flexible folder name, battery 64px, plus 48px. | Time needs more characters than an icon, and battery needs both an icon and percentage. The folder name receives extra width rather than imposing the reader's thirds. |
| List pagination | First 48px, Previous 64px, flexible page count, Next 64px, Last 48px. | Frequent single-page actions get larger targets than beginning/end jumps. The same layout serves files, apps, bookmarks, Contents, and search results. |
| Browser file rows | Flexible name plus a 72px metadata column (88px on wide screens). | Names have priority; file sizes and folder markers remain aligned in their own column. |
| Browser selection | Full-width count/header, then equal action columns with at least 120px per cell. Additional rows occupy whole existing browser bands. | Labeled actions such as Open with need more room than navigation icons. The rows wrap deliberately instead of leaving irregular button widths. |
| Browser and Apps popups | Single columns; 216px browser menu and 240px Apps menu, 56px option rows. | These are short command lists, so a simple vertical list is easier to scan than a multi-column grid. The longer Apps option gets more width. |
| Apps header | Fixed 48px navigation/action cells, 72px clock, flexible title. Search replaces the title/action region with a wide input. | Typing and filtering need width; spare space should not expand Refresh or More. App rows remain full-width names. |
| Settings | Labels above full-width controls in portrait. At 640px content width, a 176px label column aligns all controls. Font choices use thirds, margins quarters, paragraph choices halves; step controls have 56px minus/plus cells. | The number and length of choices determine each group. A single app-wide ratio would squeeze font names or waste space on short values. Adjacent enabled settings retain visible separators. |
| Secondary reader pages | Bounded 56px Back/Add/Save cells and a flexible title. Bookmarks use flexible labels plus 56px Delete cells. Contents uses a text column with bounded indentation. | List text stays readable, destructive actions have their own targets, and deep Contents nesting does not consume the entire row. |
| Search | File search: flexible query, 56px Search and Close, two equal scope choices. Book search: flexible query and 88px Search. | The word Search needs more width than its icon. Scope is a pair of comparable choices. Keyboard-resized viewports remain scrollable. |
| Form/confirmation dialogs | A readable content column capped at 480px, with equal boxed footer actions. | Related actions align and remain usable without stretching a small form across a landscape display. Dialog content scrolls above the keyboard. |
| Recovery and reader errors | Constrained readable text plus equal actions. Recovery uses three columns only when each can be 176px wide; otherwise it stacks full-width rows. | Long action labels remain readable and no lone half-width action is left on a final row. Error content scrolls when space is short. |

The file browser and app drawer retain their existing 15 portrait/12 landscape
vertical bands. Other screens keep 56px control rows and choose content heights
according to their text. The document reading surface and gestures are unchanged.

## Preview files

- [Reader, portrait](.buildlog/tab-trial-432x897.png) and [landscape](.buildlog/tab-trial-800x360.png)
- [Browser](.buildlog/browser-boxes-432x897.png), [menu](.buildlog/browser-options-432x897.png), and [selection](.buildlog/browser-selection-432x897.png)
- [Text settings](.buildlog/text-settings-432x897.png) and [landscape settings](.buildlog/text-settings-800x360.png)
- [Form dialog](.buildlog/grid-folder-dialog-432x897.png) and [recovery](.buildlog/grid-recovery-432x897.png)
- [Apps](.buildlog/apps-boxes-432x897.png), [Contents](.buildlog/toc-432x897.png), and [bookmarks](.buildlog/bookmarks-432x897.png)
- [File search](.buildlog/grid-file-search-432x897.png) and [book search](.buildlog/book-search-432x897.png)

## Verification

The full Flutter suite passes 279 tests with native PDFium stress enabled; one
external-PDF test is skipped. All 35 visual cases pass at 432×897, 800×360, and
320×640, including form/search keyboard cases. The final combined settings,
search, and preview run passes 41 checks. No device installation was performed.

These are host-rendered previews. Physical e-ink device validation remains a
separate trial step.
