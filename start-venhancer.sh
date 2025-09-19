#!/bin/bash
set -euo pipefail

LOG_PREFIX="[VEnhancer]"

log() {
    echo "${LOG_PREFIX} $*"
}

SOURCE_DIR=/opt/venhancer_source
TARGET_DIR=/workspace/VEnhancer
CKPT_DIR="$TARGET_DIR/ckpts"
RESULTS_DIR="$TARGET_DIR/results"
TMP_DIR="$TARGET_DIR/tmp"
PROMPTS_DIR=/workspace/prompts
OUTPUT_DIR=/workspace/out

log "Container start detected"

if [ ! -f "$TARGET_DIR/gradio_app.py" ]; then
    log "Restoring application files to $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    rsync -a "$SOURCE_DIR/" "$TARGET_DIR/"
else
    log "Application files already present in workspace"
fi

mkdir -p "$CKPT_DIR" "$RESULTS_DIR" "$TMP_DIR" "$PROMPTS_DIR" "$OUTPUT_DIR"

# Determine desired model variant from the requested app version
REQUESTED_VERSION=${VENHANCER_VERSION:-v1}
case "$REQUESTED_VERSION" in
    v2)
        MODEL_VARIANT="v2"
        ;;
    *)
        MODEL_VARIANT="paper"
        REQUESTED_VERSION="v1"
        ;;
esac
export VENHANCER_MODEL_VARIANT="$MODEL_VARIANT"
CHECKPOINT_REPO=${VENHANCER_CHECKPOINT_REPO:-Kijai/VEnhancer-fp16}
SAFETENSORS_FILE="venhancer_${MODEL_VARIANT}-fp16.safetensors"
TARGET_PT_FILE="$CKPT_DIR/venhancer_${MODEL_VARIANT}.pt"

# Optional Hugging Face authentication for private checkpoints
export HF_HOME=${HF_HOME:-/workspace/.cache/huggingface}
if command -v huggingface-cli >/dev/null 2>&1; then
    if [ -n "${HF_TOKEN:-}" ]; then
        log "Logging in to Hugging Face CLI"
        if ! huggingface-cli login --token "$HF_TOKEN" --no-write-token 2>/tmp/hf_login.log; then
            log "Warning: Hugging Face login failed"
            cat /tmp/hf_login.log
        else
            rm -f /tmp/hf_login.log
        fi
    else
        log "HF_TOKEN not provided; skipping Hugging Face login"
    fi
else
    log "huggingface-cli not available; skipping login"
fi

# Download and convert safetensors weights if missing
if [ -f "$TARGET_PT_FILE" ]; then
    log "Checkpoint already prepared at $TARGET_PT_FILE"
elif ! command -v huggingface-cli >/dev/null 2>&1; then
    log "huggingface-cli missing; cannot download $SAFETENSORS_FILE"
else
    log "Fetching $SAFETENSORS_FILE from $CHECKPOINT_REPO"
    if huggingface-cli download "$CHECKPOINT_REPO" "$SAFETENSORS_FILE" \
        --local-dir "$CKPT_DIR" --local-dir-use-symlinks False >/tmp/hf_download.log 2>&1; then
        log "Converting $SAFETENSORS_FILE to PyTorch checkpoint"
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
                log "Conversion completed but $TARGET_PT_FILE missing"
            fi
        else
            log "Conversion script failed for $SAFETENSORS_FILE"
        fi
    else
        log "Failed to download $SAFETENSORS_FILE; see log below"
        cat /tmp/hf_download.log
    fi
    rm -f /tmp/hf_download.log
fi

# Configure nginx authentication proxy
USERNAME=${VENHANCER_USERNAME:-admin}
PASSWORD=${VENHANCER_PASSWORD:-venhancer}
TARGET_PORT=${GRADIO_SERVER_PORT:-7860}
PROXY_PORT=${VENHANCER_ACCESS_PORT:-7862}

if ! command -v htpasswd >/dev/null 2>&1; then
    log "ERROR: htpasswd not found"
    exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
    log "ERROR: nginx not found"
    exit 1
fi

log "Configuring nginx basic authentication"
htpasswd -cb /etc/nginx/.htpasswd "$USERNAME" "$PASSWORD"

cat > /etc/nginx/conf.d/venhancer-auth.conf <<EOF_CONF
server {
    listen ${PROXY_PORT};

    location / {
        auth_basic "VEnhancer Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:${TARGET_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF_CONF

if ! grep -q "include /etc/nginx/conf.d/.*.conf;" /etc/nginx/nginx.conf; then
    log "Ensuring nginx.conf loads conf.d snippets"
    sed -i '/http {/a \	include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
fi

if ! nginx -t >/dev/null 2>&1; then
    log "ERROR: nginx configuration test failed"
    exit 1
fi

log "Reloading nginx"
if ! nginx -s reload >/dev/null 2>&1; then
    log "nginx reload failed; attempting fresh start"
    nginx -s stop >/dev/null 2>&1 || true
    nginx
fi

export GRADIO_SERVER_NAME=${GRADIO_SERVER_NAME:-127.0.0.1}
export GRADIO_SERVER_PORT=$TARGET_PORT
export VENHANCER_VERSION=$REQUESTED_VERSION
export VENHANCER_RESULTS_DIR=$RESULTS_DIR
export VENHANCER_TMP_DIR=$TMP_DIR

log "Launching VEnhancer Gradio app on port $TARGET_PORT"
cd "$TARGET_DIR"
nohup python3 gradio_app.py --version "$VENHANCER_VERSION" \
    > /workspace/venhancer.log 2>&1 &

log "VEnhancer started. Logs: /workspace/venhancer.log"
log "Auth credentials -> user: $USERNAME password: $PASSWORD"
log "External access via port $PROXY_PORT"

if [ -f "/start.sh" ]; then
    log "Delegating to RunPod base start.sh"
    exec /start.sh
else
    log "RunPod base start.sh missing; tailing application log"
    exec tail -f /workspace/venhancer.log
fi
