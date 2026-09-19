# MM Review PDFs

This folder is a **folder reference** in the Xcode project: whatever PDFs are
here get copied into the app bundle under `MMReview/`. The app indexes them
through the tracked `CFAL3/Resources/mm_review.json`, which holds only module
titles and page numbers.

**The PDFs themselves are gitignored and must never be committed.** They are
purchased MarkMeldrum.com coursework — encrypted, carrying a CFA Institute
copyright notice, and stamped with a per-purchaser watermark. This repository
is public, so committing them would republish a third party's paid product
under this account's name and expose the watermark that identifies the buyer.

The app treats missing PDFs as a normal state, not an error: MM Review lists
the books it knows about and tells you which files are absent.

Expected filenames:

| File | Book | Pages |
| --- | --- | --- |
| `mm-asset-allocation.pdf` | Asset Allocation | 87 |
| `mm-portfolio-construction.pdf` | Portfolio Construction | 104 |
| `mm-performance-measurement.pdf` | Performance Measurement | 45 |
| `mm-derivatives.pdf` | Derivatives and Risk Management | 58 |
| `mm-ethics.pdf` | Ethical and Professional Standards | 80 |
| `mm-pm-pathway.pdf` | Portfolio Management Pathway | 126 |

If you re-download a newer revision, check the page numbers still line up —
`mm_review.json` records the start and end page of every module, and the app
jumps straight to `startPage`. Each `startPage` should be that module's
learning-outcome title page.
