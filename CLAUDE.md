# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

`generate_mockups.command` is a single-file macOS batch automation tool. It drives **Adobe Photoshop 2026** via AppleScript + ExtendScript (JSX) to generate every orientation-matched combination of (mockup template PSD × source photo): replace a smart object layer, flatten, export JPEG, close without saving the template.

Orientation matching — portrait or landscape — is determined from pixel dimensions using macOS's built-in `sips`. Square images are treated as landscape. Pairs where orientations differ are silently skipped.

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
- Pre-computes orientation (`portrait`/`landscape`/`unknown`) for every PSD and photo using `sips`, storing results in parallel arrays `MOCKUP_ORIENTATIONS` and `PHOTO_ORIENTATIONS`
- Counts orientation-matched pairs upfront so progress display (`[N/total]`) is accurate
- Batch loop is index-based (`${!PHOTOS[@]}` / `${!MOCKUPS[@]}`) to look up pre-computed orientations; mismatched or unknown pairs are skipped and counted in `skipped`
- Computes the next unused letter suffix A–Z for each `NNNN_K_*.jpeg` slot (rerun-safe)
- Calls `write_jsx()` then `osascript "$AS_TEMP"` for each matched pair

**ExtendScript layer** (written into `/tmp/mockup_jsx_XXXXXX.jsx` per iteration by `write_jsx()`)
- Opens the PSD, depth-first searches all layers and nested groups for a `LayerKind.SMARTOBJECT` with the target name
- Opens the smart object via `placedLayerEditContents` action, reads its internal canvas dimensions (`soDoc.width/height.as('px')`), closes without saving — this gives the target dimensions for photo scaling
- `preparePhoto()`: opens the source JPEG in PS, scales proportionally with `resizeImage()` until both dimensions meet the canvas size (`Math.max(scaleX, scaleY)` — cover method), center-crops with `Document.crop()` using `UnitValue` pixel bounds, saves to `Folder.temp` as a JPEG, closes without saving; temp file is deleted in `finally`
- Replaces smart object contents with the prepared photo via `executeAction(stringIDToTypeID("placedLayerReplaceContents"), ...)` — preserves existing external transforms/warps/perspective
- `app.activeDocument` and `doc.activeLayer` are explicitly restored after each sub-operation that opens a document (SO editing, preparePhoto) since PS may not auto-restore focus
- Flattens, exports JPEG with `saveAs(..., asCopy=true)`, closes with `SaveOptions.DONOTSAVECHANGES`

**AppleScript bridge** (written once into `_mockup_tmp_<PID>/mockup.applescript`)
- Reads the JSX file as text and passes it to `do javascript` inside a `with timeout` block
- Written once at startup; the JSX temp path is embedded at write time

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
- **`get_orientation()`** — calls `sips -g pixelWidth -g pixelHeight` (macOS built-in, works on both JPG and PSD), parses with `awk`, returns `portrait` (height > width) or `landscape` (width ≥ height — square images are treated as landscape) or `unknown` (exit 1) if dimensions can't be read. Called once per file at startup, never per-pair.
- **`jsx_escape()`** — escapes `\` then `"` before embedding POSIX paths into JSX string literals. Any change to path embedding must go through this function.
- **Bash 3.2 compatible** — uses `while IFS= read -r` + process substitution instead of `mapfile`; index iteration via `${!array[@]}` instead of associative arrays; no `set -e` (errors handled manually).
- **`set -uo pipefail`** without `-e` — unset-variable protection and pipeline failure detection, but errors in the batch loop are caught manually so one bad pair doesn't abort the whole run.
- If `TARGET_LAYER_NAME` matches a non-SmartObject layer, the search skips it and throws `LAYER_NOT_FOUND`. The bash layer logs the error and increments the error counter without stopping.
- Summary line distinguishes `exported` / `skipped (orientation mismatch)` / `error(s)` as separate counts.
- A **"Press Return to close"** prompt at the end keeps the Terminal window open so the user can read results before it closes.
