# Screen layout decisions

Current layouts (introduced in version 1.0.8). Every screen shares rectangular
cells, permanent rules, restrained spacing, and clear selected and disabled states.
An enabled button or tappable row reverses black and white while pressed; a control
that is already selected and does nothing new stays black. Each area chooses its own
columns. Sizes are Flutter logical pixels; flexible tracks share the remaining width.

| Area | Layout | Why |
| --- | --- | --- |
| Reader status row and PDF modes | Battery, clock, page count, percentage, Contents, Settings in **1:2:3:1:1:1**. Modes in **1:1:1**. | The one place ninths help: the page-count cell lines up with the middle third of the modes. |
| Reader title bar | Home and Bookmarks **56px** each, flexible title, **96px** rotation. Below 360px: icons 48px, rotation 88px. Text search adds an icon cell. | Rotation has a word and an icon, so it needs more room. Fixed side cells keep targets usable on a phone and give landscape width to the title. |
| Reader tabs | **56px** arrows (48px on narrow screens), three **equal** tabs in between. Close targets 40px. | Every book gets equal weight; fixed arrows and close targets leave the most room for titles. |
| Browser header | Home, battery, plus: 64px each. Clock 128px. Flexible folder name. On very narrow screens the four cells shrink **1:2:1:1**. | Matching edge actions balance the bar; the double-width clock fits large text. |
| List paging | First, Previous, Next, Last: 64px each around a flexible page count. | Equal targets give the four actions equal weight. |
| Browser file rows | Flexible name plus a 72px info column (88px on wide screens). | Names come first; sizes and folder markers stay aligned. |
| Browser selection | Full-width count, then equal action cells of at least 120px. Extra rows use whole existing bands. | Labeled actions like **Open with** need more room than icons, and wrapping is deliberate rather than ragged. |
| Browser and Apps menus | Single columns: 216px (browser), 240px (Apps), 56px rows. The browser menu includes an orientation toggle. The Apps menu is hidden behind a long-press on **Paste**, even when Paste is disabled. | Short command lists scan best as one column. |
| Apps header | Fixed 48px nav/action cells, 72px clock, flexible title. Search replaces the title and actions with a wide input. | Typing needs width; spare space should not stretch Refresh or More. |
| Settings | Labels above full-width controls in portrait. At 640px wide, a 176px label column aligns the controls. Fonts in thirds, margins in quarters, paragraph choices in halves, 56px minus/plus cells. | Each group's number and length of choices decides its layout. One ratio everywhere would squeeze font names or waste space. |
| Secondary reader pages | 56px Back/Add/Save cells, flexible title. Bookmarks: flexible label plus 56px Delete. Contents: text column with bounded indent. | Text stays readable, delete has its own target, and deep nesting cannot swallow a row. |
| Search | File search: flexible query, 56px Search and Close, two equal scope choices. Book search: flexible query, 88px Search. | The word Search needs more room than its icon. Scope is a pair of equal choices. |
| Form and confirmation dialogs | Content column capped at 480px, equal boxed footer actions; content scrolls above the keyboard. | Related actions align without stretching across a landscape screen. |
| Recovery and error screens | Constrained text plus equal actions. Three columns only when each can be 176px wide; otherwise stacked full-width rows. | Long labels stay readable and no lone half-width action is left over. |

The file browser and app drawer keep their 15 portrait / 12 landscape vertical bands.
Other screens use 56px control rows with content heights set by their text. The
reading surface and gestures are unchanged.

## Previews

Host-rendered previews are in `.buildlog/` (project root), in portrait (432×897),
landscape (800×360), and narrow (320×640) sizes: reader and tabs, browser (with menu
and selection), text settings, form dialog, recovery, Apps, Contents, bookmarks, file
search, and book search.

## Verification

All 35 visual cases pass at 432×897, 800×360, and 320×640, including form and search
cases with the keyboard open. These are computer-rendered previews; they do not show
how the e-ink panel behaves. The layouts are covered in the device pass listed in
[DEVICE_TESTING.md](DEVICE_TESTING.md).
