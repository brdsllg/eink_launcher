# Tanach EPUB segment

**This folder's documentation now lives in [`docs/tanach/`](../docs/tanach/).** This
file is only a pointer, so the segment still has an entry point.

| Document | Covers |
| --- | --- |
| [`docs/tanach/README.md`](../docs/tanach/README.md) | **Read first.** Layout, build commands, syncing between machines, licensing |
| [`docs/tanach/docs/tanach-epub.md`](../docs/tanach/docs/tanach-epub.md) | Settled requirements, reader status, source limits, verification facts |
| [`docs/tanach/docs/REBUILD-EPUBS.md`](../docs/tanach/docs/REBUILD-EPUBS.md) | Plain-language guide to rebuilding the books |
| [`docs/tanach/work/legacy/README.md`](../docs/tanach/work/legacy/README.md) | What the historical one-off scripts did, and why not to rerun them |

The earlier versions of these documents are kept in
[`docs/archived/tanach/`](../docs/archived/tanach/) for history only.

`work/` holds the pipeline scripts. `outputs/` holds the generated books, the ZIPs,
and the markdown guides the pipeline rewrites itself — see
[`docs/tanach/README.md`](../docs/tanach/README.md). Do not hand-edit `outputs/`.