# Physical page buttons — version 1.0.9

Button support is enabled automatically in the document reader and paginated
lists: files, Apps, bookmarks, Contents, and book-search results.

## Supported assignments

The app accepts all three standard Android input pairs below. No in-app setup
is needed. If a device remaps its side buttons, use an assignment that sends one
of these pairs. The app does not change device-wide button settings.

| Previous | Next | Android keycodes |
| --- | --- | --- |
| Page Up | Page Down | 92 / 93 |
| Left | Right | 21 / 22 |
| Volume Up | Volume Down | 24 / 25 |

The physical top/bottom position of a button is determined by the device's
assignment; the app follows the key it receives. Firmware menus can vary, so
these are supported input mappings rather than an assumed firmware menu path.

## Reading behavior

- PDF Height: previous/next document page.
- PDF Width: previous/next screenful, continuing to the adjacent page at its edge.
- PDF Zoom / Scroll: previous/next viewport-sized step through the document.
- EPUB, TXT, and Markdown: previous/next laid-out page.
- A reader button press dismisses the reading menu and uses the same navigation
  logic as the existing touch controls. PDF turns keep their ordered queue.
- Each physical press turns once. Holding a button does not run away through
  pages. The first and last positions remain bounded.

## Input boundaries

Only the current route handles page buttons. Opening a dialog, popup, settings
screen, or another app does not turn a hidden reader or list. Paging is disabled
while a reader loads and while the file-search overlay covers the file list.
Focused text fields retain their editing keys; Ctrl, Alt, and Meta shortcuts
are not treated as page turns. Back and Power are left to the existing system
behavior. Volume mappings are consumed only by an eligible paging surface,
including at its boundaries, preventing a page-button press from also changing
volume there. Outside those surfaces, normal volume handling remains available.

## Verification and references

Host tests cover every mapping, press/repeat/release handling, synthesized-key
suppression, text focus, dialogs, routes, lifecycle, disposal, list bounds, and
actual reader navigation. Physical B751C verification remains pending.

All 293 test cases passed across the regression run and focused rerun, including
12 button-input tests, reader/list integration, and native PDFium stress. One
external-PDF test is skipped. Static analysis is clean.

Bigme identifies the original B751C's physical page buttons in its
[official product page](https://store.bigme.vip/products/bigme-7-b751c-color-epaper-notepad-with-android-11-os-copy-1)
and [linked manual, page 5](https://cdn.shopify.com/s/files/1/0629/1311/8387/files/B751C_V5.0.pdf?v=1734508307).
Flutter receives the standard Android logical keys through its existing engine
path; returning handled from the
[HardwareKeyboard handler](https://api.flutter.dev/flutter/services/HardwareKeyboard/addHandler.html)
prevents unhandled-key redispatch. No separate native key interceptor is added.
