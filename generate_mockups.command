#!/usr/bin/env bash
#
# generate_mockups.command — Photoshop batch mockup generator
#
# Double-click this file in Finder to run in Terminal.
#
# First-run macOS permission:
#   macOS will show: "Terminal wants to control Adobe Photoshop 2026"
#   Click Allow, or grant it in:
#   System Settings > Privacy & Security > Automation > Terminal
#

set -uo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
TARGET_LAYER_NAME="Photo"            # Smart Object layer name present in every PSD
PHOTOSHOP_APP="Adobe Photoshop 2026" # Exact app name (no .app suffix)
OSASCRIPT_TIMEOUT=600                # Seconds per export before AppleScript times out

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Welcome ────────────────────────────────────────────────────────────────────
printf '\n'
printf '╔══════════════════════════════════════════════════════╗\n'
printf '║        Photoshop Mockup Batch Generator              ║\n'
printf '╚══════════════════════════════════════════════════════╝\n'
printf '\n'
printf 'To copy a folder path in Finder: right-click → Copy as Pathname\n'
printf '(On older macOS: hold Option, then right-click → Copy "…" as Pathname)\n'

# ── Interactive path collection ────────────────────────────────────────────────

# ask_dir <prompt> <must_exist 0|1> — stores result in $_RESULT
_RESULT=""
ask_dir() {
    local prompt="$1" must_exist="$2"
    local path=""
    while true; do
        printf '\n%s\n→ ' "$prompt"
        read -r path
        # Strip surrounding quotes that macOS Finder may include
        path="${path#\"}" ; path="${path%\"}"
        path="${path#\'}" ; path="${path%\'}"
        # Strip trailing slash
        path="${path%/}"
        if [[ -z "$path" ]]; then
            printf 'Path cannot be empty. Try again.\n'
            continue
        fi
        if [[ "$must_exist" == "1" && ! -d "$path" ]]; then
            printf 'Folder not found: %s\nCheck the path and try again.\n' "$path"
            continue
        fi
        _RESULT="$path"
        return 0
    done
}

# ── Auto-detect folders next to the script ─────────────────────────────────────
MOCKUPS_DIR=""
PHOTOS_DIR=""
OUTPUT_DIR=""

_psd_count=0
_jpg_count=0

[[ -d "${SCRIPT_DIR}/mockups" ]] && \
    _psd_count=$(find "${SCRIPT_DIR}/mockups" -maxdepth 1 -name "*.psd" -type f | wc -l | awk '{print $1}')
[[ -d "${SCRIPT_DIR}/photos" ]] && \
    _jpg_count=$(find "${SCRIPT_DIR}/photos"  -maxdepth 1 -name "*.jpg" -type f | wc -l | awk '{print $1}')

printf '\nChecking for local folders in script directory...\n'

if [[ -d "${SCRIPT_DIR}/mockups" && $_psd_count -gt 0 \
   && -d "${SCRIPT_DIR}/photos"  && $_jpg_count -gt 0 ]]; then

    printf '  mockups/  —  %d .psd file(s)\n' "$_psd_count"
    printf '  photos/   —  %d .jpg file(s)\n' "$_jpg_count"
    printf '  output/   —  %s\n' "$([[ -d "${SCRIPT_DIR}/output" ]] && echo 'exists' || echo 'will be created')"
    printf '\nUse these folders? [Y/n] '
    read -r _ans
    case "$_ans" in
        n|N) : ;;
        *)
            MOCKUPS_DIR="${SCRIPT_DIR}/mockups"
            PHOTOS_DIR="${SCRIPT_DIR}/photos"
            OUTPUT_DIR="${SCRIPT_DIR}/output"
            ;;
    esac

else
    if [[ ! -d "${SCRIPT_DIR}/mockups" ]]; then
        printf '  mockups/  —  not found\n'
    elif [[ $_psd_count -eq 0 ]]; then
        printf '  mockups/  —  found but no .psd files inside\n'
    else
        printf '  mockups/  —  %d .psd file(s)\n' "$_psd_count"
    fi
    if [[ ! -d "${SCRIPT_DIR}/photos" ]]; then
        printf '  photos/   —  not found\n'
    elif [[ $_jpg_count -eq 0 ]]; then
        printf '  photos/   —  found but no .jpg files inside\n'
    else
        printf '  photos/   —  %d .jpg file(s)\n' "$_jpg_count"
    fi
fi

# ── Manual path prompts (only for any folder not yet resolved) ─────────────────
if [[ -z "$MOCKUPS_DIR" || -z "$PHOTOS_DIR" || -z "$OUTPUT_DIR" ]]; then
    printf '\nProvide the missing folder paths:\n'
fi

if [[ -z "$MOCKUPS_DIR" ]]; then
    ask_dir "Mockups folder (contains .psd files):" "1"
    MOCKUPS_DIR="$_RESULT"
fi

if [[ -z "$PHOTOS_DIR" ]]; then
    ask_dir "Photos folder (contains .jpg files):" "1"
    PHOTOS_DIR="$_RESULT"
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    ask_dir "Output folder (will be created if it does not exist):" "0"
    OUTPUT_DIR="$_RESULT"
fi

mkdir -p "$OUTPUT_DIR"

# ── Confirm before running ─────────────────────────────────────────────────────
printf '\n'
printf '══════════════════════════════════════════════════════\n'
printf '  Mockups folder : %s\n' "$MOCKUPS_DIR"
printf '  Photos folder  : %s\n' "$PHOTOS_DIR"
printf '  Output folder  : %s\n' "$OUTPUT_DIR"
printf '══════════════════════════════════════════════════════\n'
printf 'Ready to proceed? [Y/n] '
read -r confirm
case "$confirm" in
    n|N)
        printf 'Aborted.\n'
        printf '\nPress Return to close this window.\n'
        read -r
        exit 0
        ;;
esac

printf '\n'

# ── Collect and sort files ─────────────────────────────────────────────────────
MOCKUPS=()
while IFS= read -r f; do MOCKUPS+=("$f"); done \
    < <(find "$MOCKUPS_DIR" -maxdepth 1 -name "*.psd" -type f | sort)

PHOTOS=()
while IFS= read -r f; do PHOTOS+=("$f"); done \
    < <(find "$PHOTOS_DIR" -maxdepth 1 -name "*.jpg" -type f | sort)

if [[ ${#MOCKUPS[@]} -eq 0 ]]; then
    printf 'Error: no .psd files found in %s\n' "$MOCKUPS_DIR" >&2
    printf '\nPress Return to close this window.\n' ; read -r ; exit 1
fi
if [[ ${#PHOTOS[@]} -eq 0 ]]; then
    printf 'Error: no .jpg files found in %s\n' "$PHOTOS_DIR" >&2
    printf '\nPress Return to close this window.\n' ; read -r ; exit 1
fi

# ── Helper: next unused filename suffix for output slot NNNN_K ────────────────
# Returns "" on first use (→ NNNN_K.jpg), then "_A", "_B", … on reruns.
next_suffix() {
    local nnnn="$1" k="$2" letter
    [[ ! -e "${OUTPUT_DIR}/${nnnn}_${k}.jpg" ]] && { printf ''; return 0; }
    for letter in {A..Z}; do
        [[ ! -e "${OUTPUT_DIR}/${nnnn}_${k}_${letter}.jpg" ]] && {
            printf '_%s' "$letter"
            return 0
        }
    done
    printf 'Error: all slots exhausted for %s_%s(_A-Z).jpg\n' "$nnnn" "$k" >&2
    return 1
}

# ── Helper: escape a POSIX path for a JSX double-quoted string literal ─────────
jsx_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ── Helper: portrait or landscape from pixel dimensions via sips ───────────────
get_orientation() {
    local file="$1" dims w h
    dims=$(sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null)
    w=$(printf '%s' "$dims" | awk '/pixelWidth:/  {print $2}')
    h=$(printf '%s' "$dims" | awk '/pixelHeight:/ {print $2}')
    if [[ -z "$w" || -z "$h" || "$w" -eq 0 || "$h" -eq 0 ]] 2>/dev/null; then
        printf 'unknown'
        return 1
    fi
    if (( h > w )); then printf 'portrait'
    else                 printf 'landscape'
    fi
}

# ── Pre-compute orientations for all PSDs and photos ──────────────────────────
printf 'Reading orientations...\n'

MOCKUP_ORIENTATIONS=()
for psd in "${MOCKUPS[@]}"; do
    orient="unknown"
    orient=$(get_orientation "$psd") || \
        printf 'Warning: cannot read dimensions for %s — will be skipped\n' \
            "$(basename "$psd")" >&2
    MOCKUP_ORIENTATIONS+=("$orient")
done

PHOTO_ORIENTATIONS=()
for photo in "${PHOTOS[@]}"; do
    orient="unknown"
    orient=$(get_orientation "$photo") || \
        printf 'Warning: cannot read dimensions for %s — will be skipped\n' \
            "$(basename "$photo")" >&2
    PHOTO_ORIENTATIONS+=("$orient")
done

# Count orientation-matched pairs for accurate progress display
total=0
for pi in "${!PHOTOS[@]}"; do
    for mi in "${!MOCKUPS[@]}"; do
        if [[ "${PHOTO_ORIENTATIONS[$pi]}" != "unknown" \
           && "${PHOTO_ORIENTATIONS[$pi]}" == "${MOCKUP_ORIENTATIONS[$mi]}" ]]; then
            total=$(( total + 1 ))
        fi
    done
done

# ── Temp files ─────────────────────────────────────────────────────────────────
# All temp files live in one folder next to the script so the trap can nuke
# the whole directory on exit — including any prep JPEGs orphaned by a PS crash.
TEMP_DIR="${SCRIPT_DIR}/_mockup_tmp_$$"
mkdir -p "$TEMP_DIR"
JSX_TEMP="${TEMP_DIR}/mockup.jsx"
AS_TEMP="${TEMP_DIR}/mockup.applescript"
trap 'rm -rf "$TEMP_DIR"' EXIT

# AppleScript driver — written once; reads JSX_TEMP (updated per iteration)
# and hands the source text to Photoshop's do javascript command.
cat > "$AS_TEMP" <<ASEOF
set jsCode to read (POSIX file "${JSX_TEMP}") as text
with timeout of ${OSASCRIPT_TIMEOUT} seconds
    tell application "${PHOTOSHOP_APP}"
        do javascript jsCode
    end tell
end timeout
ASEOF

# ── JSX writer: embeds per-iteration paths into the ExtendScript source ────────
write_jsx() {
    local psd="$1" photo="$2" out="$3" layer="$4"
    local ep eh eo el et
    ep=$(jsx_escape "$psd")
    eh=$(jsx_escape "$photo")
    eo=$(jsx_escape "$out")
    el=$(jsx_escape "$layer")
    et=$(jsx_escape "$TEMP_DIR")

    cat > "$JSX_TEMP" <<JSXEOF
(function () {
    var psdPath     = "${ep}";
    var photoPath   = "${eh}";
    var outputPath  = "${eo}";
    var targetLayer = "${el}";
    var tempDir     = "${et}";

    var savedDialogs = app.displayDialogs;
    app.displayDialogs = DialogModes.NO;

    // Depth-first search through all layers and nested groups.
    function findSmartObject(layers, name) {
        for (var i = 0; i < layers.length; i++) {
            var lyr = layers[i];
            if (lyr.name === name && lyr.kind === LayerKind.SMARTOBJECT) {
                return lyr;
            }
            if (lyr.typename === "LayerSet") {
                var hit = findSmartObject(lyr.layers, name);
                if (hit) return hit;
            }
        }
        return null;
    }

    // Scale-to-fill (cover): proportionally scale until both dimensions meet
    // the target, then center-crop. Returns a temp File with the result.
    function preparePhoto(sourcePath, targetW, targetH, targetRes) {
        var srcDoc = app.open(new File(sourcePath));
        var srcW   = srcDoc.width.as('px');
        var srcH   = srcDoc.height.as('px');

        var scale = Math.max(targetW / srcW, targetH / srcH);
        var newW  = Math.ceil(srcW * scale);
        var newH  = Math.ceil(srcH * scale);

        // Resolution must match the smart object's internal resolution, not
        // the source photo's — placedLayerReplaceContents scales the placed
        // transform using PPI-aware physical size, not raw pixel count, so a
        // resolution mismatch (e.g. a 72ppi photo replacing 300ppi-calibrated
        // content) blows up the on-canvas box even when pixel dimensions match.
        srcDoc.resizeImage(
            UnitValue(newW, 'px'),
            UnitValue(newH, 'px'),
            targetRes,
            ResampleMethod.BICUBIC
        );

        var cropL = Math.floor((newW - targetW) / 2);
        var cropT = Math.floor((newH - targetH) / 2);
        srcDoc.crop([
            UnitValue(cropL,           'px'),
            UnitValue(cropT,           'px'),
            UnitValue(cropL + targetW, 'px'),
            UnitValue(cropT + targetH, 'px')
        ]);

        srcDoc.flatten();

        var tmp      = new File(tempDir + '/prep_' + (new Date()).getTime() + '.jpg');
        var jpegOpts = new JPEGSaveOptions();
        jpegOpts.quality = 12;
        srcDoc.saveAs(tmp, jpegOpts, true);
        srcDoc.close(SaveOptions.DONOTSAVECHANGES);

        return tmp;
    }

    var doc;
    var preparedFile = null;
    try {
        var psdFile = new File(psdPath);
        if (!psdFile.exists) {
            throw new Error("PSD file not found: " + psdPath);
        }

        doc = app.open(psdFile);

        var smartLayer = findSmartObject(doc.layers, targetLayer);
        if (!smartLayer) {
            throw new Error(
                "LAYER_NOT_FOUND: no SmartObject named \\"" + targetLayer +
                "\\" in " + psdPath
            );
        }

        doc.activeLayer = smartLayer;

        // Read the smart object's internal canvas dimensions straight off the
        // layer's Action Manager descriptor (smartObjectMore.size). This avoids
        // placedLayerEditContents, which was found to reset the nonAffineTransform
        // corner data on Perspective-transformed smart objects even when the
        // opened contents are closed without saving.
        var canvasW, canvasH, canvasRes;
        try {
            var layerRef = new ActionReference();
            layerRef.putEnumerated(charIDToTypeID("Lyr "), charIDToTypeID("Ordn"), charIDToTypeID("Trgt"));
            var layerDesc = executeActionGet(layerRef);
            var somDesc   = layerDesc.getObjectValue(stringIDToTypeID("smartObjectMore"));
            var sizeDesc  = somDesc.getObjectValue(stringIDToTypeID("size"));
            canvasW   = Math.round(sizeDesc.getDouble(stringIDToTypeID("width")));
            canvasH   = Math.round(sizeDesc.getDouble(stringIDToTypeID("height")));
            canvasRes = somDesc.getUnitDoubleValue(stringIDToTypeID("resolution"));
        } catch (dimErr) {
            throw new Error(
                "Could not read Smart Object dimensions for \\"" + targetLayer +
                "\\": " + dimErr.message
            );
        }

        // Scale photo to fill the smart object canvas (cover, no squeeze).
        // preparePhoto opens a new PS document; restore parent focus after.
        preparedFile       = preparePhoto(photoPath, canvasW, canvasH, canvasRes);
        app.activeDocument = doc;
        doc.activeLayer    = smartLayer;

        // Replace embedded contents. All existing external transforms, warps,
        // and perspective distortions on the smart object layer are preserved.
        var replDesc = new ActionDescriptor();
        replDesc.putPath(charIDToTypeID("null"), preparedFile);
        executeAction(
            stringIDToTypeID("placedLayerReplaceContents"),
            replDesc,
            DialogModes.NO
        );

        doc.flatten();

        var jpegOpts             = new JPEGSaveOptions();
        jpegOpts.quality         = 12;
        jpegOpts.embedColorProfile = true;
        jpegOpts.formatOptions   = FormatOptions.STANDARDBASELINE;
        jpegOpts.matte           = MatteType.NONE;

        // asCopy = true: writes the JPEG without updating the document's native
        // save path, so close(DONOTSAVECHANGES) below discards all in-memory edits
        // and leaves the template PSD on disk exactly as it was.
        doc.saveAs(new File(outputPath), jpegOpts, true);

    } finally {
        if (preparedFile !== null && preparedFile.exists) {
            preparedFile.remove();
        }
        app.displayDialogs = savedDialogs;
        if (typeof doc !== "undefined") {
            doc.close(SaveOptions.DONOTSAVECHANGES);
        }
    }
})();
JSXEOF
}

# ── Orientation breakdown for header ──────────────────────────────────────────
m_portrait=0; m_landscape=0
for o in "${MOCKUP_ORIENTATIONS[@]}"; do
    case "$o" in
        portrait)  m_portrait=$(( m_portrait + 1 ))  ;;
        landscape) m_landscape=$(( m_landscape + 1 )) ;;
    esac
done

p_portrait=0; p_landscape=0
for o in "${PHOTO_ORIENTATIONS[@]}"; do
    case "$o" in
        portrait)  p_portrait=$(( p_portrait + 1 ))  ;;
        landscape) p_landscape=$(( p_landscape + 1 )) ;;
    esac
done

printf 'Mockups : %d PSDs  (portrait: %d, landscape: %d)\n' \
    "${#MOCKUPS[@]}" "$m_portrait" "$m_landscape"
printf 'Photos  : %d JPGs  (portrait: %d, landscape: %d)\n' \
    "${#PHOTOS[@]}" "$p_portrait" "$p_landscape"
printf 'Matching: %d exports\n' "$total"
printf 'Output  : %s\n' "$OUTPUT_DIR"
printf '%s\n' '──────────────────────────────────────────────────────'

if [[ $total -eq 0 ]]; then
    printf 'Warning: no orientation-matched pairs found. Nothing to do.\n' >&2
    printf '\nPress Return to close this window.\n' ; read -r ; exit 0
fi

# ── Batch loop ─────────────────────────────────────────────────────────────────
counter=0
skipped=0
errors=0
pad=${#total}

for pi in "${!PHOTOS[@]}"; do
    photo="${PHOTOS[$pi]}"
    photo_orient="${PHOTO_ORIENTATIONS[$pi]}"
    photo_base=$(basename "$photo")

    nnnn=$(printf '%s' "$photo_base" | grep -oE '^[0-9]{4}' || true)
    if [[ -z "$nnnn" ]]; then
        printf 'Warning: no 4-digit prefix in "%s" — skipping photo\n' "$photo_base" >&2
        errors=$(( errors + 1 ))
        continue
    fi

    for mi in "${!MOCKUPS[@]}"; do
        psd="${MOCKUPS[$mi]}"
        psd_orient="${MOCKUP_ORIENTATIONS[$mi]}"
        k=$(( mi + 1 ))

        if [[ "$photo_orient" == "unknown" || "$psd_orient" == "unknown" \
           || "$photo_orient" != "$psd_orient" ]]; then
            skipped=$(( skipped + 1 ))
            continue
        fi

        counter=$(( counter + 1 ))

        suffix=$(next_suffix "$nnnn" "$k") || {
            errors=$(( errors + 1 ))
            continue
        }

        out_file="${nnnn}_${k}${suffix}.jpg"
        out_path="${OUTPUT_DIR}/${out_file}"

        printf '[%0'"$pad"'d/%0'"$pad"'d] %s  %s\n' \
            "$counter" "$total" "$out_file" "$photo_orient"

        write_jsx "$psd" "$photo" "$out_path" "$TARGET_LAYER_NAME"

        if ! err_msg=$(osascript "$AS_TEMP" 2>&1); then
            printf '  Error [%s × %s]: %s\n' \
                "$nnnn" "$(basename "$psd")" "$err_msg" >&2
            errors=$(( errors + 1 ))
        fi
    done
done

printf '%s\n' '──────────────────────────────────────────────────────'
printf 'Done. %d/%d exported, %d skipped (orientation mismatch), %d error(s).\n' \
    "$(( counter - errors ))" "$counter" "$skipped" "$errors"

printf '\nPress Return to close this window.\n'
read -r
