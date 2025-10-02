#!/usr/bin/env bash
set -euo pipefail

DEST=${1:-"$HOME/.mjvoice/fluid"}
BIN_DIR="$DEST/bin"
MODEL_CACHE="${MJVOICE_FLUID_MODEL_CACHE:-$DEST/models}"
VENV_DIR="$DEST/.venv"

info() { printf "[fluid] %s\n" "$*"; }
warn() { printf "[fluid][warn] %s\n" "$*" >&2; }

if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is required to install the Fluid runtime."
    exit 1
fi

info "Preparing directories under $DEST"
mkdir -p "$BIN_DIR" "$MODEL_CACHE"

if [ ! -d "$VENV_DIR" ]; then
    info "Creating virtual environment"
    python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

info "Upgrading pip"
pip install --upgrade pip >/dev/null
info "Installing runtime dependencies (faster-whisper, soundfile)"
pip install --upgrade faster-whisper soundfile >/dev/null

echo "#!/usr/bin/env python3" > "$BIN_DIR/fluid_runner.py"
cat <<'PY' >> "$BIN_DIR/fluid_runner.py"
import argparse
import json
import os
import sys
from pathlib import Path

try:
    import soundfile as sf
    from faster_whisper import WhisperModel
except Exception as exc:  # pragma: no cover
    print(f"Failed to load Fluid runtime dependencies: {exc}", file=sys.stderr)
    sys.exit(2)

MODEL_MAP = {
    "fluid-light": "Systran/faster-whisper-tiny",
    "fluid-pro": "Systran/faster-whisper-base",
    "fluid-advanced": "Systran/faster-whisper-small",
}


def resolve_model(args):
    if args.model_path:
        path = Path(args.model_path)
        if path.is_file():
            return str(path.parent)
        return str(path)
    identifier = MODEL_MAP.get(args.model_id, args.model_id)
    return identifier


def main():
    parser = argparse.ArgumentParser(description="mjvoice Fluid runtime wrapper")
    parser.add_argument("--model-path", help="Path to a local CTranslate2 model directory", default=None)
    parser.add_argument("--model-id", help="Model identifier (Hugging Face or shortcut)", default="fluid-advanced")
    parser.add_argument("--audio", required=True, help="Path to the WAV file to transcribe")
    parser.add_argument("--format", default="json", choices=["json", "text"], help="Output format")
    parser.add_argument("--cache-dir", default=os.environ.get("MJVOICE_FLUID_MODEL_CACHE", os.path.expanduser("~/.mjvoice/fluid/models")))
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()

    model_arg = resolve_model(args)
    kwargs = {
        "device": args.device,
        "compute_type": "int8",
    }
    if args.model_path:
        kwargs["download_root"] = args.cache_dir
    else:
        kwargs["download_root"] = args.cache_dir

    model = WhisperModel(model_arg, **kwargs)

    try:
        audio, sample_rate = sf.read(args.audio)
    except Exception as exc:
        print(f"Failed to read audio file {args.audio}: {exc}", file=sys.stderr)
        sys.exit(3)

    segments, info = model.transcribe(
        audio,
        beam_size=1,
        language=None,
        temperature=0.0,
        vad_filter=True,
    )

    texts = []
    for segment in segments:
        texts.append({
            "start": segment.start,
            "end": segment.end,
            "text": segment.text.strip(),
        })

    combined = " ".join(t["text"] for t in texts).strip()

    if args.format == "json":
        print(json.dumps({"text": combined, "segments": [t["text"] for t in texts]}, ensure_ascii=False))
    else:
        print(combined)


if __name__ == "__main__":  # pragma: no cover
    main()
PY
chmod +x "$BIN_DIR/fluid_runner.py"

echo "#!/usr/bin/env bash" > "$BIN_DIR/fluid-runner"
cat <<'SH' >> "$BIN_DIR/fluid-runner"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/.venv"
if [ ! -d "$VENV" ]; then
    echo "Fluid runtime virtualenv not found. Re-run tools/install_fluid_runner.sh." >&2
    exit 1
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python3 "$ROOT/bin/fluid_runner.py" "$@"
SH
chmod +x "$BIN_DIR/fluid-runner"

info "Prefetching baseline Fluid models (this can take a few minutes)"
python3 - <<'PY'
import os
from faster_whisper import WhisperModel

cache = os.environ.get("MJVOICE_FLUID_MODEL_CACHE", os.path.expanduser("~/.mjvoice/fluid/models"))
os.makedirs(cache, exist_ok=True)
for model_id in ["Systran/faster-whisper-tiny", "Systran/faster-whisper-base", "Systran/faster-whisper-small"]:
    print(f"[fluid] downloading {model_id} …")
    WhisperModel(model_id, device="cpu", compute_type="int8", download_root=cache)
PY

APP_BIN="$HOME/Library/Application Support/mjvoice/bin"
mkdir -p "$APP_BIN"
ln -sf "$BIN_DIR/fluid-runner" "$APP_BIN/fluid-runner"

info "Fluid runtime installed at $BIN_DIR/fluid-runner"
