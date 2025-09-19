#!/bin/bash
set -euo pipefail

LOG_PREFIX="[VEnhancer-Restart]"
log() {
    echo "${LOG_PREFIX} $*"
}

TARGET_DIR=${VENHANCER_ROOT:-/workspace/VEnhancer}
LOG_PATH=${VENHANCER_LOG_PATH:-/workspace/venhancer.log}
VERSION=${VENHANCER_VERSION:-v1}
SERVER_NAME=${GRADIO_SERVER_NAME:-0.0.0.0}
SERVER_PORT=${GRADIO_SERVER_PORT:-7860}

if [ ! -d "$TARGET_DIR" ]; then
    log "ERROR: target directory $TARGET_DIR not found"
    exit 1
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
