# Photoshop Mockup Batch Generator — Spec

## Goal

Build a macOS automation script that batch-generates product mockups using Adobe Photoshop 2026, driven from the command line with **no external dependencies** (no Python/Node, no Photoshop plugins) — just bash, AppleScript (`osascript`), and ExtendScript (JSX) run inside Photoshop via `do javascript`.

For every combination of (mockup template × source photo), replace a smart object layer in the mockup PSD with the photo, then export a flattened JPEG.

## Inputs

Passed as CLI arguments: ./run_mockups.sh <mockups_folder> <photos_folder> <output_folder>

1. **Mockups folder** — contains PSD files with random, non-numeric filenames. Each PSD has exactly one smart object layer, and every PSD uses the same consistent layer name for it. Make this a configurable constant near the top of the script, `TARGET_LAYER_NAME`, default `"Photo"`.
2. **Photos folder** — contains JPGs named like `0001_Ratio_2x3_small.jpg`, `0002_Ratio_2x3_small.jpg`, etc. The leading 4-digit sequence number (`NNNN`) is the identifier to extract.
3. **Output folder** — flat, no subfolders.

## Processing logic

- Sort the mockup PSDs alphabetically by filename. Assign each an index `K` (1, 2, 3...) based on that sort order for this run — this order does not need to stay stable across runs.
- For each photo (extract `NNNN` from its filename) × each mockup (`K`):
  - Open the PSD in Photoshop.
  - Find the smart object layer matching `TARGET_LAYER_NAME`.
  - Replace its embedded contents with the current photo file (Photoshop's "Replace Contents" for smart objects — must preserve any existing transform/warp/perspective already applied to that smart object).
  - Flatten the image.
  - Export as JPEG at the PSD's native canvas dimensions (no resizing), at maximum JPEG quality (12).
  - Close the PSD without saving changes to the template.
  - Save the export to the output folder as `NNNN_K_X.jpeg`, where `X` is a letter starting at `A`. Before writing, check the output folder for existing files matching `NNNN_K_*.jpeg` and pick the next unused letter (so reruns never overwrite previous exports — they just add `_B`, `_C`, etc.).

## Implementation notes

- Use `osascript -e 'tell application "Adobe Photoshop 2026" to do javascript "..."'` (or write the JSX to a temp file and have AppleScript execute it via `File`) to drive Photoshop. Exact app name: `"Adobe Photoshop 2026"` (no `.app`).
- **Bash layer** handles: argument parsing, globbing/sorting the mockup files, parsing `NNNN` from photo filenames, and computing the next unused `_X` letter suffix per output file.
- **JSX layer** handles: opening the doc, locating the smart object by layer name (search top-level layers; note if it should also search inside groups), replacing contents, flattening, and exporting.
- Handle the case where a PSD doesn't contain a layer named `TARGET_LAYER_NAME` — log a clear error and skip that mockup rather than crashing the whole batch.
- Add basic progress output to the terminal, e.g.: [0007/0020] mockup 3/5: 0007_3_A.jpeg
- First run requires a one-time macOS Automation permission grant (Terminal → control Adobe Photoshop) — flag this if it comes up.

## Deliverable

A single `run_mockups.sh` (with either inline JSX via heredoc or a companion `.jsx` file, whichever is cleaner). Walk through testing it against one mockup and one photo before running the full batch.