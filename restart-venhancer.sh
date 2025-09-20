#!/bin/bash
set -euo pipefail

LOG_PREFIX="[VEnhancer-Restart]"
log() {
    echo "${LOG_PREFIX} $*"
}

usage() {
    cat <<'USAGE'
Usage: restart-venhancer [--version v1|v2]

Stops the running Gradio app, clears CUDA cache, ensures the requested
checkpoint is present, then relaunches VEnhancer.
USAGE
}

TARGET_DIR=${VENHANCER_ROOT:-/workspace/VEnhancer}
LOG_PATH=${VENHANCER_LOG_PATH:-/workspace/venhancer.log}
VERSION=${VENHANCER_VERSION:-v2}
SERVER_NAME=${GRADIO_SERVER_NAME:-0.0.0.0}
SERVER_PORT=${GRADIO_SERVER_PORT:-7860}
CHECKPOINT_REPO=${VENHANCER_CHECKPOINT_REPO:-Kijai/VEnhancer-fp16}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            if [[ $# -lt 2 ]]; then
                log "ERROR: --version requires an argument (v1 or v2)"
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

case "$VERSION" in
    v2)
        MODEL_VARIANT="v2"
        ;;
    v1)
        MODEL_VARIANT="paper"
        ;;
    *)
        log "ERROR: Unsupported version '$VERSION'. Use v1 or v2."
        exit 1
        ;;
esac

export VENHANCER_VERSION="$VERSION"
export VENHANCER_MODEL_VARIANT="$MODEL_VARIANT"

CKPT_DIR="$TARGET_DIR/ckpts"
SAFETENSORS_FILE="venhancer_${MODEL_VARIANT}-fp16.safetensors"
TARGET_PT_FILE="$CKPT_DIR/venhancer_${MODEL_VARIANT}.pt"
export HF_HOME=${HF_HOME:-/workspace/.cache/huggingface}

if [ ! -d "$TARGET_DIR" ]; then
    log "ERROR: target directory $TARGET_DIR not found"
    exit 1
fi

mkdir -p "$CKPT_DIR"

log "Ensuring checkpoint for version ${VERSION} (${MODEL_VARIANT})"
if [ -f "$TARGET_PT_FILE" ]; then
    log "Checkpoint found at $TARGET_PT_FILE"
elif ! command -v huggingface-cli >/dev/null 2>&1; then
    log "ERROR: huggingface-cli not available; cannot download checkpoint"
    exit 1
else
    tmp_log=$(mktemp /tmp/venhancer_restart_download.XXXXXX.log)
    log "Downloading $SAFETENSORS_FILE from $CHECKPOINT_REPO"
    if huggingface-cli download "$CHECKPOINT_REPO" "$SAFETENSORS_FILE" \
        --local-dir "$CKPT_DIR" --local-dir-use-symlinks False >>"$tmp_log" 2>&1; then
        log "Converting $SAFETENSORS_FILE to PyTorch format"
        if SRC_PATH="$CKPT_DIR/$SAFETENSORS_FILE" DST_PATH="$TARGET_PT_FILE" python3 - <<'PY'
import os
import sys
from pathlib import Path

import torch
from safetensors.torch import load_file

src = Path(os.environ["SRC_PATH"])
dst = Path(os.environ["DST_PATH"])

if not src.exists():
    print(f"Conversion skipped: {src} missing", file=sys.stderr)
    sys.exit(1)

state_dict = load_file(src)
torch.save({"state_dict": state_dict}, dst)
print(f"Saved PyTorch checkpoint to {dst}")
PY
        then
            if [ -f "$TARGET_PT_FILE" ]; then
                log "Checkpoint ready at $TARGET_PT_FILE"
            else
                log "ERROR: Conversion finished but $TARGET_PT_FILE not found"
                cat "$tmp_log"
                rm -f "$tmp_log"
                exit 1
            fi
        else
            log "ERROR: Conversion script failed"
            cat "$tmp_log"
            rm -f "$tmp_log"
            exit 1
        fi
    else
        log "ERROR: Failed to download checkpoint"
        cat "$tmp_log"
        rm -f "$tmp_log"
        exit 1
    fi
    rm -f "$tmp_log"
fi

log "Stopping existing VEnhancer processes (if any)"
if pkill -f "python3 gradio_app.py" >/dev/null 2>&1; then
    sleep 2
    log "Existing process terminated"
else
    log "No running VEnhancer process detected"
fi

log "Clearing CUDA caches"
python3 - <<'PY' || true
import gc
try:
    import torch
except ModuleNotFoundError:
    torch = None

gc.collect()
if torch is not None and torch.cuda.is_available():
    torch.cuda.empty_cache()
    torch.cuda.ipc_collect()
PY

log "Restarting VEnhancer (version=${VERSION})"
cd "$TARGET_DIR"
nohup env \
    GRADIO_SERVER_NAME="$SERVER_NAME" \
    GRADIO_SERVER_PORT="$SERVER_PORT" \
    VENHANCER_VERSION="$VERSION" \
    python3 gradio_app.py --version "$VERSION" \
    > "$LOG_PATH" 2>&1 &
NEW_PID=$!
log "VEnhancer restarted (pid $NEW_PID). Logs: $LOG_PATH"
