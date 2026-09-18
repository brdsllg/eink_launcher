# Physical page buttons — introduced in version 1.0.9

Button support is enabled automatically in the document reader, in the paginated
lists (files, Apps, bookmarks, Contents, and book-search results), and on the
scrolling screens (the file-search results panel and the reader settings list),
where one press moves one screenful.

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
- PDF Zoom / Scroll: previous/next screenful through the document, retaining
  the overlap percentage selected in settings at the current zoom level.
- In Width and Zoom / Scroll, forward turns with overlap show inward arrows
  at both screen edges where the previous screen ended. Reading continuation
  arrows default to enabled and can be turned off in PDF settings. They clear
  on backward turns, jumps, changes to settings or viewport size, and manual
  pans or pinches.
- EPUB, TXT, and Markdown: previous/next laid-out page.
- A reader button press dismisses the reading menu and uses the same navigation
  logic as the existing touch controls. PDF turns keep their ordered queue.
- Each physical press turns once. Holding a button does not run away through
  pages. The first and last positions remain bounded.
- Reader settings offer independent toggles for physical page buttons and the
  left/right page-turn tap zones. Both default to enabled. Disabling tap zones
  keeps center-tap menu access and swipe/pinch gestures available. Disabling
  physical buttons in the reader leaves their normal system handling available.
- The file-search results panel and the reader settings list are continuous
  scroll views, so a press moves them by one screenful instead of turning a
  page. Both are bounded: a press that cannot move further is still consumed,
  so a volume-mapped button never leaks into the system volume there.

## Input boundaries

Only the current route handles page buttons. Opening a dialog, popup, settings
screen, or another app does not turn a hidden reader or list. Paging is disabled
while a reader loads and for the file list behind an open file-search overlay;
the overlay's own results panel pages. Focused text fields retain their editing
keys, and Ctrl, Alt, and Meta shortcuts are not treated as page turns. A surface
whose own search field keeps focus while it lists results - the file-search
results panel - opts into paging anyway, so page up/down and volume still move
the results while left/right stay that field's caret keys. Back and Power are
left to the existing system behavior. Volume mappings are consumed only by an
eligible paging surface, including at its boundaries, preventing a page-button
press from also changing volume there. Outside those surfaces, normal volume
handling remains available.

## Verification and references

Host tests cover every mapping, press/repeat/release handling, synthesized-key
suppression, text focus, dialogs, routes, lifecycle, disposal, list and scroll
bounds, and the real screens: the file browser, the Apps drawer, Contents,
reader search results, and the file-search results panel.

The focused button-input run passes 23 tests, and static analysis is clean. The
full suite run against this source passed 371 tests with three skipped native
PDFium checks (they need `PDF_NATIVE_STRESS` or `PDFIUM_PATH`) and no failures;
the earlier `page_button_scope_test.dart` failure no longer reproduces. Physical
B751C verification remains pending.

Bigme identifies the original B751C's physical page buttons in its
[official product page](https://store.bigme.vip/products/bigme-7-b751c-color-epaper-notepad-with-android-11-os-copy-1)
and [linked manual, page 5](https://cdn.shopify.com/s/files/1/0629/1311/8387/files/B751C_V5.0.pdf?v=1734508307).
Flutter receives the standard Android logical keys through its existing engine
path; returning handled from the
[HardwareKeyboard handler](https://api.flutter.dev/flutter/services/HardwareKeyboard/addHandler.html)
prevents unhandled-key redispatch. No separate native key interceptor is added.
