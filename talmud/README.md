# Talmud EPUB pipeline

**This folder's documentation now lives in [`docs/talmud/`](../docs/talmud/).** This
file is only a pointer, so the segment still has an entry point.

| Document | Covers |
| --- | --- |
| [`docs/talmud/README.md`](../docs/talmud/README.md) | What the segment produces, folder layout, build steps, licensing |
| [`docs/talmud/HOW-TO-SYNC.md`](../docs/talmud/HOW-TO-SYNC.md) | Fetching Sefaria data and running the build |
| [`docs/talmud/docs/talmud-epub-plan.md`](../docs/talmud/docs/talmud-epub-plan.md) | Settled decisions and open questions for the pipeline |
| [`docs/talmud/docs/reader-device-findings.md`](../docs/talmud/docs/reader-device-findings.md) | Device findings and the scale-up analysis |

The earlier versions of these documents are kept in
[`docs/archived/talmud/`](../docs/archived/talmud/) for history only.

`work/` holds the pipeline scripts. `outputs/` holds generated books, reports, and
the markdown files the pipeline writes itself — see
[`docs/talmud/README.md`](../docs/talmud/README.md). Do not hand-edit `outputs/`.