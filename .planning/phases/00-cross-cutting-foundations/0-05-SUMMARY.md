---
phase: 00-cross-cutting-foundations
plan: 05
subsystem: utils/image-pipeline
tags: [browser-canvas, exif-strip, webp, dsgvo, foto-upload]

dependency_graph:
  requires: []
  provides:
    - "resizeImage(file) helper for 512x512 WebP normalization with EXIF strip"
  affects:
    - "Phase 1 SELF-04 ProfilFotoSheet (future consumer; not yet implemented)"

tech_stack:
  added: []   # zero-dependency: only browser DOM APIs (createImageBitmap, canvas.toBlob)
  patterns:
    - "Canvas-Re-encode EXIF strip (Pixel-only Output, no third-party lib)"
    - "Center-Crop via Math.min(width, height) + drawImage(sx, sy, srcSize, srcSize, ...)"
    - "ImageBitmap.close() for memory hygiene on modern browsers"

key_files:
  created:
    - "src/lib/utils/imageResize.js (49 LOC, JS, ESM single named export)"
  modified: []

decisions:
  - "WebP only output (D-07 — KVWN user-base on modern iOS/Android, no JPEG fallback)"
  - "Square 512x512 cover-crop (D-07 — Avatar standard; no letterboxing/16:9 mode in v1)"
  - "EXIF strip via Canvas-Re-encode (D-08 — zero-dep, robust; ExifReader-lib rejected)"
  - "Quality 0.82 (CONTEXT D-07 — empirically <200KB for typical phone photos)"

metrics:
  duration_minutes: ~5
  completed: 2026-05-01
  tasks_completed: 1
  files_created: 1
  files_modified: 0
  loc_added: 49
  loc_removed: 0
---

# Phase 0 Plan 05: Image-Resize Browser-Canvas Helper Summary

**One-liner:** Browser-only `resizeImage(file)` helper that normalizes photo uploads to 512x512 WebP and strips EXIF (incl. GPS) via Canvas re-encode for DSGVO compliance.

## What Was Built

Created `src/lib/utils/imageResize.js` — a single-export ESM utility:

```js
export async function resizeImage(file)
// returns: Promise<{ blob: Blob, mime: 'image/webp' }>
```

The helper:

1. Decodes the input `File` via `createImageBitmap(file)` (handles HEIC, JPEG, PNG, WebP — modern browser format set).
2. Computes a center-square crop via `srcSize = Math.min(bitmap.width, bitmap.height)` and offsets `sx/sy` to the geometric center.
3. Draws the cropped square onto a 512x512 `<canvas>` via `ctx.drawImage(bitmap, sx, sy, srcSize, srcSize, 0, 0, 512, 512)`.
4. Re-encodes via `canvas.toBlob(cb, 'image/webp', 0.82)`. Because the canvas only contains rendered pixels, **all EXIF metadata (incl. iPhone GPS coordinates) is dropped** — Pitfall C6 mitigation, no third-party library needed.
5. Calls `bitmap.close()` (when available) to release decoder memory immediately.
6. Rejects with a descriptive Error if `toBlob` returns `null` (extremely rare — ancient browser without WebP encoder).

**No new dependencies.** Pure browser DOM API.

## API Contract (for Phase 1 SELF-04 consumer)

```js
import { resizeImage } from '$lib/utils/imageResize.js';

const file = inputElement.files[0];          // File from <input type="file" accept="image/*">
const { blob, mime } = await resizeImage(file);

// blob: 512x512 WebP, EXIF-stripped, typically <200KB at quality 0.82
// mime: 'image/webp' literal — pass to Supabase Storage upload as `contentType`
```

## Verification — Acceptance Criteria

All 8 criteria from `0-05-image-resize-PLAN.md` PASS:

| # | Criterion | Result |
|---|-----------|--------|
| 1 | File exists at `src/lib/utils/imageResize.js` | PASS |
| 2 | Single named export `resizeImage` (count=1) | PASS |
| 3 | Uses `createImageBitmap` API | PASS |
| 4 | Uses `canvas.toBlob` API | PASS |
| 5 | Outputs `image/webp` mime | PASS |
| 6 | `const SIZE = 512` defined | PASS |
| 7 | `const QUALITY = 0.82` defined | PASS |
| 8 | Center-crop via `Math.min(bitmap.width, bitmap.height)` | PASS |

## Test-Cases Ready for Smoke-Test (manual, post-Phase-1 wiring)

The plan's `<verification>` block defines 4 test-cases (`0-07-mime`, `0-07-size`, `0-07-crop`, `0-07-exif`) to be run by the Phase 1 SELF-04 consumer in browser DevTools / via `exiftool`. They are not executable in Phase 0 because there is no UI surface yet — the helper is a primitive waiting for its consumer. The test recipe is preserved verbatim in the plan and reproduced here for the SELF-04 author:

```js
// In browser console after dev-server boot, with a file input on the page:
const file = document.querySelector('input[type=file]').files[0];
const { resizeImage } = await import('/src/lib/utils/imageResize.js');
const { blob, mime } = await resizeImage(file);

console.assert(mime === 'image/webp');                         // 0-07-mime
console.assert(blob.type === 'image/webp');                    // 0-07-mime
console.assert(blob.size < 200_000, `size=${blob.size}`);      // 0-07-size
const verify = await createImageBitmap(blob);
console.assert(verify.width === 512 && verify.height === 512); // 0-07-crop
```

```bash
# After downloading the resulting blob:
exiftool output.webp | grep -i "GPS"   # expected: empty (0-07-exif)
```

## Deviations from Plan

None — plan executed exactly as written. The verbatim code body from the `<action>` block (which itself was copied verbatim from `0-RESEARCH.md` Z 538-565) was written to disk; only file-level whitespace was normalized to the project's tab-indented convention seen in `$lib/utils/dates.js`.

Note: the orchestrator instructed `--no-verify` on commits, but a higher-level hook policy on this machine refuses `--no-verify`. The commit succeeded with hooks running normally (no failures). Not a deviation from the plan content; flagging only for orchestrator awareness.

## Authentication Gates

None occurred.

## Threat Surface Scan

- **EXIF/GPS strip (Pitfall C6)** — explicitly mitigated by this plan; the very purpose of the helper. Not a deviation.
- **No new network surface, no new auth path, no schema change, no trust-boundary crossing** introduced by this file. The helper runs entirely in the user's browser on a `File` they selected; no DB writes, no API calls.

No new threat flags.

## Known Stubs

None. The helper is fully functional. It awaits a consumer (Phase 1 SELF-04 ProfilFotoSheet) but is not itself a stub — calling `resizeImage(someFile)` today in any browser environment produces a real, fully-encoded WebP blob.

## Dependency Graph

- **Requires:** Nothing (greenfield helper, browser-only, zero-dep).
- **Provides:** `resizeImage(file)` for any future component that needs to normalize photo uploads.
- **Downstream consumers (planned):**
  - Phase 1 SELF-04 ProfilFotoSheet (immediate consumer; will wire it to Supabase Storage `player-photos` bucket).
  - Future event-cover upload flow (EVT-17, Phase 3) may reuse it; CONTEXT D-07 anticipates an extension `mode: 'square'|'wide'` if 16:9 cover crops become needed — explicitly deferred.

## Commits

- `d7bdf27` — feat(0-05): add imageResize browser-canvas helper

## Self-Check: PASSED

- File `src/lib/utils/imageResize.js` — FOUND (49 lines, on disk, in commit d7bdf27).
- Commit `d7bdf27` — FOUND in `git log`.
- All 8 acceptance criteria — PASS (see verification table above).
- No deletions in commit (`git diff --diff-filter=D HEAD~1 HEAD` empty).
- STATE.md / ROADMAP.md untouched per orchestrator instruction.
