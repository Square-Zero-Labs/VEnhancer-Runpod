# VEnhancer RunPod Template

This repository packages the [VEnhancer](https://github.com/Vchitect/VEnhancer) Gradio demo for RunPod. The container boots the model UI, protects it with an nginx basic-auth proxy, and optionally downloads the Kijai FP16 checkpoints on startup.

## Contents

- `Dockerfile` &mdash; builds on `runpod/pytorch` and layers the VEnhancer application.
- `start-venhancer.sh` &mdash; RunPod-friendly entrypoint that restores the app into `/workspace`, provisions checkpoints, configures authentication, and launches Gradio.
- `docker-build.yml` &mdash; GitHub Actions workflow that builds/pushes the image on `main`, `docker`, or semantic tags.

## Building

Local build test:

```bash
docker build -t venhancer-runpod:latest .
```

Push the repository and GitHub Actions (`docker-build.yml`) will handle builds for `main`, the `docker` branch, and `v*` tags.

## Deploying On RunPod

1. Create a **Custom Template** pointing to your published image.
2. Set runtime environment variables as needed:
   - `VENHANCER_USERNAME` (default `admin`)
   - `VENHANCER_PASSWORD` (default `venhancer`)
   - `VENHANCER_VERSION` (`v1` ➜ v1/paper checkpoint, `v2` ➜ v2 checkpoint)
   - `HF_TOKEN` (optional &ndash; required when the checkpoint repo needs authentication)
3. Expose port **7862** in RunPod; the container maps nginx → Gradio (7860) internally.
4. Launch the pod and open the forwarded 7862 endpoint in your browser. Authenticate with the username/password above. (Gradio listens on `0.0.0.0:7860`; nginx proxies to 7862.)

The startup script writes logs to `/workspace/venhancer.log`. If the checkpoint already exists in `/workspace/VEnhancer/ckpts`, it is reused and no download occurs.

## Updating Credentials

To set the default UI password in a template, supply environment overrides:

```text
VENHANCER_USERNAME=myuser
VENHANCER_PASSWORD=supersecret
```

If you forget the credentials, redeploy with updated environment variables or remove `/workspace/VEnhancer` and restart the pod.

## Accessing Jupyter

The RunPod base image ships with Jupyter services reachable via the usual ports. To inspect the Jupyter token/password inside the running pod, open a terminal and run:

```bash
jupyter server list
```

Copy the `token=...` value and use in jupyter.

## Tail Application Logs

From the RunPod terminal:

```bash
tail -f /workspace/venhancer.log
```

For Docker-based local testing:

```bash
docker logs -f <container-name>
```

## Restarting the Service

If VRAM stays allocated after a heavy run, restart the Gradio process without rebooting the pod:

```bash
restart-venhancer
```

The helper stops the current process, flushes CUDA caches, and relaunches the UI using the existing environment settings.

## Checkpoint Handling

- By default the startup script downloads `venhancer_<variant>-fp16.safetensors` from `Kijai/VEnhancer-fp16` and converts it to `venhancer_<variant>.pt`.
- Override the source repository via `VENHANCER_CHECKPOINT_REPO` if you host your own weights.
- Set `HF_TOKEN` before launch when download access requires authentication.

Enjoy enhancing videos with VEnhancer on RunPod!
