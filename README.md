# Photoshop Mockup Batch Generator

A macOS automation script that batch-generates product mockups using Adobe Photoshop 2026. For every matched combination of mockup template and source photo, it replaces a smart object layer with the photo and exports a flattened JPEG — all driven from a single double-clickable script with no external dependencies.

## Requirements

- macOS
- Adobe Photoshop 2026
- No other dependencies — uses only bash, `sips`, and `osascript` (all built into macOS)

## Setup

```
your-project-folder/
├── generate_mockups.command   ← the script
├── mockups/                   ← put your PSD templates here
├── photos/                    ← put your source JPGs here
└── output/                    ← exports land here (created automatically)
```

If you place folders named `mockups/`, `photos/`, and `output/` next to the script, it will detect them automatically on launch.

Make the script executable once after cloning:

```bash
chmod +x generate_mockups.command
```

## Usage

Double-click `generate_mockups.command` in Finder. Terminal opens and walks you through setup.

**Providing folder paths:** right-click any folder in Finder → **Copy as Pathname**, then paste into the prompt. On older macOS, hold Option before right-clicking.

The script will:
1. Check for `mockups/`, `photos/`, and `output/` folders next to the script
2. If found and populated, show file counts and ask whether to use them
3. Otherwise prompt for each folder path manually
4. Show a summary and ask for confirmation before starting

### First-run permission

On the first run macOS will show:

> *"Terminal wants to control Adobe Photoshop 2026"*

Click **Allow**. If you miss it, grant access manually at:
`System Settings > Privacy & Security > Automation > Terminal`

Photoshop does not need to be open — the script launches it automatically.

## How it works

**Orientation matching** — pixel dimensions are read from every PSD and every photo using `sips`. Portrait and landscape files are matched to each other; mismatched pairs are skipped silently. Square images are treated as landscape.

**Smart object replacement** — for each matched pair the script opens the PSD, locates the smart object layer named `Photo` (searched recursively through all groups and folders), reads its internal canvas dimensions, scales the source photo to fill that canvas using a cover method (proportional scale + center crop, no squeezing), and replaces the embedded contents. All existing transforms, warps, and perspective distortions on the smart object are preserved.

**Export** — the document is flattened and saved as a JPEG at maximum quality (Photoshop quality 12) at the PSD's native canvas size. The PSD template is closed without saving, leaving it unchanged on disk.

## Output naming

| Situation | Filename |
|---|---|
| First export of a slot | `NNNN_K.jpg` |
| File already exists (rerun) | `NNNN_K_A.jpg`, `NNNN_K_B.jpg`, … |

- `NNNN` — 4-digit prefix from the source photo filename (e.g. `0042` from `0042_Ratio_2x3_small.jpg`)
- `K` — 1-based index of the PSD template in alphabetical sort order

Reruns never overwrite existing exports.

## Configuration

Three constants at the top of the script can be changed without touching anything else:

| Variable | Default | Description |
|---|---|---|
| `TARGET_LAYER_NAME` | `Photo` | Name of the smart object layer in every PSD |
| `PHOTOSHOP_APP` | `Adobe Photoshop 2026` | Exact app name passed to AppleScript |
| `OSASCRIPT_TIMEOUT` | `600` | Seconds before a single export times out |
