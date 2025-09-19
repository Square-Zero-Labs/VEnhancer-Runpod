# VEnhancer Runpod template image
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    SHELL=/bin/bash

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System packages needed for VEnhancer and runtime services
RUN rm -f /etc/apt/sources.list.d/cuda*.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        git-lfs \
        ffmpeg \
        libsm6 \
        libxext6 \
        nginx \
        apache2-utils \
        rsync \
        unzip \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN git lfs install

# Preload VEnhancer source to a safe location
ARG VENHANCER_REPO=https://github.com/Vchitect/VEnhancer.git
ARG VENHANCER_COMMIT=80ffaa33988c583b129b730ce9d559b114de2d8c
RUN git clone --depth 1 "$VENHANCER_REPO" /opt/venhancer_source && \
    cd /opt/venhancer_source && \
    git fetch origin $VENHANCER_COMMIT && \
    git checkout $VENHANCER_COMMIT && \
    rm -rf .git

# Python dependencies
RUN python3 -m pip install --upgrade pip wheel && \
    python3 -m pip install --no-cache-dir -r /opt/venhancer_source/requirements.txt && \
    python3 -m pip install --no-cache-dir safetensors==0.4.3 && \
    rm -rf /root/.cache/pip

# Copy startup helper
COPY start-venhancer.sh /usr/local/bin/start-venhancer.sh
RUN chmod +x /usr/local/bin/start-venhancer.sh

EXPOSE 7862 8888

CMD ["/usr/local/bin/start-venhancer.sh"]
