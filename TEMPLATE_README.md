# VEnhancer RunPod Template

Welcome! This template launches the VEnhancer Gradio UI on RunPod so you can upscale and enhance video clips with the latest V2 checkpoint by default.

## What Is VEnhancer?

VEnhancer applies a generative diffusion model to improve video fidelity and motion. It can increase spatial resolution, boost frame rate, and remix prompts for creative variations. The template bundles the model, UI, and helper scripts so you can get started without manual setup.

## Quick Start

1. **Deploy the template** using your RunPod account.
2. **Open the app**: Open the app on port `7862`.
3. **Log in** when prompted:
   - Username: `admin`
   - Password: `venhancer`
     Override these in the template variables (`VENHANCER_USERNAME`, `VENHANCER_PASSWORD`).
4. **Upload a clip**, enter a prompt, and click **Generate**. The result panel displays the enhanced MP4.

## Environment Variables

| Variable                                    | Description                                        | Default                |
| ------------------------------------------- | -------------------------------------------------- | ---------------------- |
| `VENHANCER_VERSION`                         | Model checkpoint (`v2` or `v1`).                   | `v2`                   |
| `VENHANCER_USERNAME` / `VENHANCER_PASSWORD` | Credentials for the nginx proxy.                   | `admin` / `venhancer`  |
| `HF_TOKEN`                                  | Optional Hugging Face token for gated checkpoints. | _unset_                |
| `VENHANCER_CHECKPOINT_REPO`                 | Alternate repo for safetensors (if self-hosted).   | `Kijai/VEnhancer-fp16` |

## Outputs & Audio

- Generated clips are saved to `/workspace/VEnhancer/results` and are also available via the Gradio UI.
- The template copies the input clip’s audio track into the rendered video automatically when audio is present.

## Logs & Monitoring

- Main logs: `/workspace/venhancer.log`
- Tail in terminal: `tail -f /workspace/venhancer.log`
- Jupyter token: `jupyter server list`

## Restart Helper

If you need to clear GPU memory or switch checkpoints:

```bash
restart-venhancer            # restarts with the current version
restart-venhancer --version v1   # switches to the paper checkpoint
```

The script stops the Gradio process, frees CUDA cache, ensures the requested checkpoint is downloaded, and relaunches the UI.

## Troubleshooting

- **Large clips OOM:** Reduce `up_scale`, trim duration, or decrease target FPS.
- **Checkpoint download fails:** make sure `HF_TOKEN` is set if the repository is gated.
- **Auth issues:** redeploy with new `VENHANCER_USERNAME` / `VENHANCER_PASSWORD` values.

## Resources

- The [Dockerfile and code](https://github.com/Square-Zero-Labs/VEnhancer-Runpod) are open source. If you encounter any problems, please open an issue in the repo.
- [VEnhancer Repo](https://github.com/Vchitect/VEnhancer)
- [Video demo](https://youtu.be/rYDeopPdQz8)

Enjoy enhancing your videos with VEnhancer on RunPod!
