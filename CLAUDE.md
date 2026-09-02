# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

`generate_mockups.command` is a single-file macOS batch automation tool. It drives **Adobe Photoshop 2026** via AppleScript + ExtendScript (JSX) to generate every orientation-matched combination of (mockup template PSD × source photo): replace a smart object layer, flatten, export JPEG, close without saving the template.

Orientation matching — portrait or landscape — is determined from pixel dimensions. Photos use macOS's built-in `sips`; PSDs are probed through Photoshop instead, reading the *target Smart Object's* internal canvas size rather than the PSD document's outer canvas (a template's document canvas can be a different orientation, or square, while the smart object placed inside it is portrait/landscape — `sips` on the PSD file can't see that). A square photo counts as landscape. A square Smart Object is its own category and matches *either* portrait or landscape photos (a 1:1 target doesn't force the aggressive crop that orientation matching otherwise exists to avoid). Non-square pairs where orientations differ are silently skipped.

No external runtimes — only bash, `sips`, `osascript`, and Photoshop's built-in ExtendScript engine.

## Running

Double-click `generate_mockups.command` in Finder. Terminal opens and prompts for three folder paths interactively.

To copy a folder path in Finder: right-click → **Copy as Pathname** (hold Option first on older macOS).

At startup the script checks for `mockups/`, `photos/`, and `output/` folders sitting next to the script file. If `mockups/` contains `.psd` files and `photos/` contains `.jpg` files, it shows the file counts and asks **"Use these folders? [Y/n]"** — skipping manual prompts entirely on Y. If any folder is missing or empty, it reports which ones and falls back to asking for paths manually.

When prompting manually, only the unresolved folders are asked for (e.g. if auto-detect found mockups but not photos, only photos is prompted).

Then shows a summary and asks **"Ready to proceed? [Y/n]"** before starting.

**First run only:** macOS shows *"Terminal wants to control Adobe Photoshop 2026"* — click Allow, or grant it at `System Settings > Privacy & Security > Automation > Terminal`.

**One-time setup:** `chmod +x generate_mockups.command` (already done; only needed after re-cloning).

## Configuration constants (top of script)

| Variable | Default | Purpose |
|---|---|---|
| `TARGET_LAYER_NAME` | `"Photo"` | Exact name of the Smart Object layer in every PSD |
| `PHOTOSHOP_APP` | `"Adobe Photoshop 2026"` | App name passed to `tell application` |
| `OSASCRIPT_TIMEOUT` | `600` | Seconds before AppleScript times out per image |

## Architecture

The script has two distinct layers that communicate through temp files:

**Bash layer** (`generate_mockups.command`, main body)
- Interactive prompts collect the three folder paths; `ask_dir()` uses a global `_RESULT` variable to return values from the function (avoids subshell `read` issues)
- Collects `*.psd` files sorted alphabetically, assigns K=1,2,3… as mockup index
- Collects `*.jpg` files, extracts 4-digit `NNNN` prefix from each filename
- Pre-computes orientation (`portrait`/`landscape`/`unknown`) for every PSD and photo — PSDs via `get_psd_orientation()` (opens each PSD in Photoshop once via a probe JSX, see below), photos via `get_orientation()` (`sips`) — storing results in parallel arrays `MOCKUP_ORIENTATIONS` and `PHOTO_ORIENTATIONS`
- Counts orientation-matched pairs upfront so progress display (`[N/total]`) is accurate
- Batch loop is index-based (`${!PHOTOS[@]}` / `${!MOCKUPS[@]}`) to look up pre-computed orientations; mismatched or unknown pairs are skipped and counted in `skipped`
- Computes the next unused letter suffix A–Z for each `NNNN_K_*.jpeg` slot (rerun-safe)
- Calls `write_jsx()` then `osascript "$AS_TEMP"` for each matched pair

**ExtendScript layer** (written into `_mockup_tmp_<PID>/mockup.jsx`, overwritten per call by `write_jsx()` or `write_probe_jsx()`)
- `write_probe_jsx()` generates a lightweight probe script, run once per PSD *before* the batch loop (via `get_psd_orientation()`): opens the PSD, finds the target Smart Object, reads its `smartObjectMore.size` off the layer descriptor, and `return`s `"<width>,<height>"` as the script's value — `do javascript`'s return value is what `osascript` prints to stdout, which the bash layer parses. Closes the doc without saving either way. On failure (missing file/layer) it throws, `osascript` exits non-zero, and `get_psd_orientation()` reports `unknown`.
- `write_jsx()` (the actual replace-and-export script) opens the PSD, depth-first searches all layers and nested groups for a `LayerKind.SMARTOBJECT` with the target name
- Reads the smart object's internal canvas dimensions **and resolution** via `executeActionGet` on the active layer reference — `smartObjectMore.size.width/height` and `smartObjectMore.resolution` in the descriptor — instead of opening the smart object's contents via `placedLayerEditContents` (that approach was tried and abandoned; see below).
- `preparePhoto()`: opens the source JPEG in PS, scales proportionally with `resizeImage()` until both dimensions meet the canvas size (`Math.max(scaleX, scaleY)` — cover method), center-crops with `Document.crop()` using `UnitValue` pixel bounds, saves to `Folder.temp` as a JPEG, closes without saving; temp file is deleted in `finally`. **Resolution passed to `resizeImage()` must be the smart object's own resolution (`canvasRes`), not `srcDoc.resolution`** — see below.
- Replaces smart object contents with the prepared photo via `executeAction(stringIDToTypeID("placedLayerReplaceContents"), ...)` — preserves existing external transforms/warps/perspective
- `app.activeDocument` and `doc.activeLayer` are explicitly restored after `preparePhoto()` (which opens a separate document) since PS may not auto-restore focus
- Flattens, exports JPEG with `saveAs(..., asCopy=true)`, closes with `SaveOptions.DONOTSAVECHANGES`

**AppleScript bridge** (written once into `_mockup_tmp_<PID>/mockup.applescript`)
- Reads the JSX file as text and passes it to `do javascript` inside a `with timeout` block
- Written once at startup; the JSX temp path is embedded at write time; reused as-is for both the per-PSD orientation probe and the per-pair replace/export, since it just relays whatever's currently in the JSX temp file and returns/prints `do javascript`'s result

**Temp file strategy** — all temp files live in `_mockup_tmp_<PID>/` next to the script (`SCRIPT_DIR` is resolved via `cd "$(dirname "$0")" && pwd`). The bash `trap 'rm -rf "$TEMP_DIR"' EXIT` nukes the entire folder on exit — including any prep JPEGs orphaned by a Photoshop crash mid-iteration. The `tempDir` path is embedded into each JSX so `preparePhoto()` writes there instead of the system `/tmp/`.

## Output naming

- First export of a slot: `NNNN_K.jpg` — e.g. `0007_3.jpg`
- Reruns (file already exists): `NNNN_K_A.jpg`, `NNNN_K_B.jpg`, … — e.g. `0007_3_A.jpg`
- `NNNN`: 4-digit prefix from the photo filename
- `K`: 1-based PSD index (alphabetical order, this run only — not stable across runs)

`next_suffix()` returns `""` when the base file is absent, `"_A"` / `"_B"` / … otherwise.

## Key implementation details

- **`SCRIPT_DIR`** — resolved early via `cd "$(dirname "$0")" && pwd` so it's available for both auto-detect and the temp folder path.
- **Auto-detect** — counts `*.psd` and `*.jpg` files in `$SCRIPT_DIR/mockups` and `$SCRIPT_DIR/photos` using `find | wc -l | awk`. Only prompts for folders that couldn't be resolved automatically.
- **`ask_dir()`** — interactive prompt with validation loop; uses global `_RESULT` to return a value because `read` inside `$()` subshells doesn't connect to the terminal.
- **`get_orientation()`** — calls `sips -g pixelWidth -g pixelHeight` (macOS built-in), parses with `awk`, returns `portrait` (height > width) or `landscape` (width ≥ height — square images are treated as landscape) or `unknown` (exit 1) if dimensions can't be read. **Photos only** — see `get_psd_orientation()` for PSDs. Called once per file at startup, never per-pair.
- **`get_psd_orientation()`** — orientation for PSDs, resolved through Photoshop rather than `sips`. Writes a probe JSX via `write_probe_jsx()`, runs it through the shared `$AS_TEMP` AppleScript bridge, and parses the `"<width>,<height>"` string `do javascript` returns (validated against `^[0-9]+,[0-9]+$`; anything else — non-zero exit, missing/malformed output — is treated as `unknown`). Returns `portrait`, `landscape`, `square` (`width == height`, unlike `get_orientation()` which folds square into landscape), or `unknown`. Called once per PSD at startup, before the batch loop, so it costs one extra Photoshop open/close per template but never per pair.
  - **Why not `sips` on the PSD file:** `sips` reads the PSD *document's* outer canvas dimensions. The target Smart Object's own internal canvas (what `preparePhoto()` actually scales the photo to) can be a different orientation — e.g. a square or landscape document canvas containing a portrait-oriented smart object placement. Checking the document canvas caused portrait smart objects to be classified as landscape and matched against wide photos, which were then stretched to fill a tall placement. Fixed by reading the same `smartObjectMore.size` descriptor that `write_jsx()` already uses for scaling, instead of the file's own pixel dimensions.
- **`orientation_matches(photo_orient, psd_orient)`** — the single source of truth for whether a pair is compatible, used both when pre-counting `total` and in the batch loop's skip check (previously duplicated as a plain equality test in each place). `unknown` on either side never matches; a `square` PSD orientation matches both `portrait` and `landscape` photos; otherwise the two must be equal. Photos are never classified `square` themselves (see `get_orientation()`), so this asymmetry is intentional — only a PSD's target Smart Object can be square.
- **`jsx_escape()`** — escapes `\` then `"` before embedding POSIX paths into JSX string literals. Any change to path embedding must go through this function.
- **Bash 3.2 compatible** — uses `while IFS= read -r` + process substitution instead of `mapfile`; index iteration via `${!array[@]}` instead of associative arrays; no `set -e` (errors handled manually).
- **`set -uo pipefail`** without `-e` — unset-variable protection and pipeline failure detection, but errors in the batch loop are caught manually so one bad pair doesn't abort the whole run.
- If `TARGET_LAYER_NAME` matches a non-SmartObject layer, the search skips it and throws `LAYER_NOT_FOUND`. The bash layer logs the error and increments the error counter without stopping.
- Summary line distinguishes `exported` / `skipped (orientation mismatch)` / `error(s)` as separate counts.
- A **"Press Return to close"** prompt at the end keeps the Terminal window open so the user can read results before it closes.
- **Perspective-transformed smart objects need matching resolution, not just matching pixel dimensions.** `placedLayerReplaceContents` scales the placed transform using PPI-aware physical size, not raw pixel count. A replacement photo with correct pixel dimensions but a different resolution than the smart object's internal document (e.g. a 72ppi photo replacing 300ppi-calibrated content) causes Photoshop to massively rescale the on-canvas transform — visible as an oversized, offset, unwarped photo on templates with a Perspective transform on the target layer (diagnosed via a before/after dump of `smartObjectMore.transform`/`nonAffineTransform`: the box grew ~4.78× on a resolution-mismatched replace with no pixel-size change to match). Fixed by reading `smartObjectMore.resolution` off the layer descriptor and passing it through to `preparePhoto()`'s `resizeImage()` call instead of `srcDoc.resolution`.
- **`placedLayerEditContents` (opening a smart object's contents to read its size) was tried and abandoned** as the way to get canvas dimensions — replaced with reading `smartObjectMore.size`/`resolution` off the layer's Action Manager descriptor via `executeActionGet`, which doesn't require opening anything. This didn't turn out to be the source of the transform bug (that was the resolution mismatch above), but is still the right approach: it's fewer document open/close cycles and one less thing that could theoretically disturb layer state mid-batch.
