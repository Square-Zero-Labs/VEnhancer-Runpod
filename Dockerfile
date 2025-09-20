# VEnhancer Runpod template image (torch 2.2.1 + Python 3.10)
FROM runpod/pytorch:2.2.1-py3.10-cuda12.1.1-devel-ubuntu22.04

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
        build-essential \
        ninja-build \
        cmake \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN git lfs install

# Preload bundled VEnhancer source (checked in via subtree)
COPY VEnhancer-base /opt/venhancer_source

# Python dependencies
RUN python3 -m pip install --upgrade pip wheel && \
    python3 -m pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cu121 \
        -r /opt/venhancer_source/requirements.txt && \
    python3 -m pip install --no-cache-dir gradio==5.35.0 gradio_client>=1.4.0 safetensors==0.4.3 && \
    rm -rf /root/.cache/pip

# Copy runtime helpers
COPY start-venhancer.sh /usr/local/bin/start-venhancer.sh
COPY restart-venhancer.sh /usr/local/bin/restart-venhancer
RUN chmod +x /usr/local/bin/start-venhancer.sh \
    /usr/local/bin/restart-venhancer

EXPOSE 7862 8888

CMD ["/usr/local/bin/start-venhancer.sh"]
