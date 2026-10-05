# Physical page buttons

Introduced in version 1.0.9. Button support is on automatically in the reader and in
paginated lists: files, Apps, bookmarks, Contents, and book-search results.

## Supported button pairs

The app accepts all three standard Android pairs below, with no in-app setup. If a
device remaps its side buttons, assign one of these pairs. The app never changes
device-wide button settings.

| Previous | Next | Android keycodes |
| --- | --- | --- |
| Page Up | Page Down | 92 / 93 |
| Left | Right | 21 / 22 |
| Volume Up | Volume Down | 24 / 25 |

Which physical button is "previous" depends on the device's assignment; the app
follows the key it receives.

## Troubleshooting: buttons seem dead

On the Bigme, side buttons can be assigned per app. An assignment that sends none of
the pairs above makes the buttons look dead in this app while they still work
elsewhere, and no rebuild can fix that. On 18 Sept 2026 the buttons stopped working
here (surviving a force stop, reboot, and reinstall); assigning the side buttons to
**D-pad Left/Right** in the Bigme settings fixed it immediately. When reporting a
button problem, note the device's current button assignment.

## Reading behavior

- **PDF Height:** previous/next page.
- **PDF Width:** previous/next screenful, continuing to the adjacent page at the
  edge.
- **PDF Zoom / Scroll:** previous/next screenful, keeping the overlap percentage from
  settings at the current zoom.
- **Overlap arrows:** in Width and Zoom / Scroll, forward turns with overlap show
  inward arrows at both screen edges where the previous screen ended. They are on by
  default and can be turned off in PDF settings. They clear on backward turns, jumps,
  setting or size changes, and manual pans or pinches.
- **EPUB, TXT, Markdown:** previous/next laid-out page.
- A button press hides the reading menu and uses the same navigation as touch. PDF
  turns keep their ordered queue.
- Each press turns once; holding does not run through pages. The first and last
  positions are bounded.
- Reader settings have separate toggles for physical buttons and for the left/right
  tap zones (both on by default). Turning off tap zones keeps centre-tap menu access,
  swipes, and pinches. Turning off buttons returns them to normal system handling.

## When buttons are ignored

- Only the current screen handles buttons. A dialog, popup, settings screen, or
  another app never turns a hidden reader or list.
- Paging is off while a reader loads and while the file-search overlay covers the list.
- Text fields keep their editing keys; Ctrl, Alt, and Meta shortcuts are not page
  turns. Back and Power keep their system behavior.
- Volume keys are consumed only by a paging screen (including at its boundaries), so
  a page turn never also changes volume there. Elsewhere, volume works normally.

## Verification

Host tests cover every mapping, press/repeat/release handling, synthesized keys, text
focus, dialogs, routes, lifecycle, list bounds, and real reader navigation. The
buttons are confirmed working on the Bigme test device (history in
[DEVICE_TESTING.md](DEVICE_TESTING.md)).

## References

Bigme documents the original B751C's page buttons on its
[product page](https://store.bigme.vip/products/bigme-7-b751c-color-epaper-notepad-with-android-11-os-copy-1)
and in the [manual, page 5](https://cdn.shopify.com/s/files/1/0629/1311/8387/files/B751C_V5.0.pdf?v=1734508307).
Flutter receives the standard Android keys through its normal path; handling them in
the
[HardwareKeyboard handler](https://api.flutter.dev/flutter/services/HardwareKeyboard/addHandler.html)
stops them being passed on again. No separate native key interceptor is used.
