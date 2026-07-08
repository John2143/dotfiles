import sys
import types

# Compat shim: torchvision 0.25 removed functional_tensor, but basicsr (dependency
# of realesrgan) still imports rgb_to_grayscale from there. See xinntao/Real-ESRGAN#859.
try:
    from torchvision.transforms.functional_tensor import rgb_to_grayscale  # noqa: F401
except ImportError:
    from torchvision.transforms.functional import rgb_to_grayscale
    functional_tensor = types.ModuleType("torchvision.transforms.functional_tensor")
    functional_tensor.rgb_to_grayscale = rgb_to_grayscale
    sys.modules["torchvision.transforms.functional_tensor"] = functional_tensor


import os
import io
import torch
import numpy as np
from PIL import Image
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import Response
from realesrgan import RealESRGANer
from basicsr.archs.rrdbnet_arch import RRDBNet
import urllib.request

from swinir_arch import SwinIR

app = FastAPI(title="Image Upscaler")

DEFAULT_MODEL = os.environ.get("ESRGAN_MODEL", "swinir-psnr")
TILE = int(os.environ.get("ESRGAN_TILE", "400"))

WEIGHTS_DIR = os.path.expanduser("~/.cache/realesrgan")

# ---------------------------------------------------------------------------
# Model registry
# ---------------------------------------------------------------------------

MODEL_REGISTRY = {
    "swinir-psnr": {
        "display": "SwinIR-L x4 PSNR (real-world SR, no hallucination)",
        "scale": 4,
        "backend": "swinir",
    },
    "realesrgan": {
        "display": "Real-ESRGAN x4plus (general-purpose, GAN-enhanced)",
        "scale": 4,
        "backend": "realesrgan",
    },
    "realesrgan-anime": {
        "display": "Real-ESRGAN x4plus anime (anime-optimized)",
        "scale": 4,
        "backend": "realesrgan",
    },
    "realesrgan-x2": {
        "display": "Real-ESRGAN x2plus (2x upscaling)",
        "scale": 2,
        "backend": "realesrgan",
    },
}

REALESRGAN_MODEL_URLS = {
    "realesrgan": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
    "realesrgan-anime": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth",
    "realesrgan-x2": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth",
}

SWINIR_WEIGHT_URL = (
    "https://github.com/JingyunLiang/SwinIR/releases/download/v0.0/"
    "003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_PSNR.pth"
)
SWINIR_WEIGHT_NAME = "003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_PSNR.pth"

# Lazy-loaded model instances
_models = {}


# ---------------------------------------------------------------------------
# Model loaders
# ---------------------------------------------------------------------------

def _load_realesrgan(model_key: str):
    """Load a Real-ESRGAN model."""
    from realesrgan import RealESRGANer
    from basicsr.archs.rrdbnet_arch import RRDBNet

    url = REALESRGAN_MODEL_URLS[model_key]
    filename = os.path.basename(url)
    model_path = os.path.join(WEIGHTS_DIR, filename)

    if not os.path.exists(model_path):
        os.makedirs(WEIGHTS_DIR, exist_ok=True)
        print(f"Downloading Real-ESRGAN weights: {url}")
        urllib.request.urlretrieve(url, model_path)

    scale = MODEL_REGISTRY[model_key]["scale"]
    model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32, scale=scale)
    use_half = torch.cuda.is_available()
    print(f"Loading Real-ESRGAN ({model_key}): scale={scale}, half={use_half}, tile={TILE}")
    return RealESRGANer(
        scale=scale,
        model_path=model_path,
        model=model,
        tile=TILE,
        tile_pad=10,
        pre_pad=0,
        half=use_half,
    )


def _load_swinir():
    """Load SwinIR-L x4 PSNR for real-world SR with zero hallucination."""
    model_path = os.path.join(WEIGHTS_DIR, SWINIR_WEIGHT_NAME)

    if not os.path.exists(model_path):
        os.makedirs(WEIGHTS_DIR, exist_ok=True)
        print(f"Downloading SwinIR weights: {SWINIR_WEIGHT_URL}")
        urllib.request.urlretrieve(SWINIR_WEIGHT_URL, model_path)

    # SwinIR-L config for real-world SR (task=real_sr, --large_model).
    # Exact config from the official main_test_swinir.py define_model().
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = SwinIR(
        upscale=4,
        in_chans=3,
        img_size=64,
        window_size=8,
        img_range=1.0,
        depths=[6, 6, 6, 6, 6, 6, 6, 6, 6],
        embed_dim=240,
        num_heads=[8, 8, 8, 8, 8, 8, 8, 8, 8],
        mlp_ratio=2,
        upsampler="nearest+conv",
        resi_connection="3conv",
    )

    print(f"Loading SwinIR weights from {model_path}")
    checkpoint = torch.load(model_path, map_location=device, weights_only=True)
    # PSNR variant uses 'params' key (GAN variant uses 'params_ema')
    param_key = "params" if "params" in checkpoint else "params_ema"
    model.load_state_dict(checkpoint[param_key], strict=True)
    model.eval()
    model = model.to(device)
    print(f"SwinIR-L x4 PSNR loaded on {device}")
    return model


def get_model(model_key: str):
    """Lazy-load and cache model instances."""
    if model_key in _models:
        return _models[model_key]

    if model_key not in MODEL_REGISTRY:
        valid = ", ".join(MODEL_REGISTRY.keys())
        raise ValueError(f"Unknown model: {model_key}. Valid: {valid}")

    backend = MODEL_REGISTRY[model_key]["backend"]
    if backend == "realesrgan":
        _models[model_key] = _load_realesrgan(model_key)
    elif backend == "swinir":
        _models[model_key] = _load_swinir()
    else:
        raise ValueError(f"Unknown backend: {backend}")

    return _models[model_key]


# ---------------------------------------------------------------------------
# Inference helpers
# ---------------------------------------------------------------------------

def upscale_realesrgan(img_np, model_key: str, outscale: int = 4):
    """Run Real-ESRGAN inference."""
    upsampler = get_model(model_key)
    output, _ = upsampler.enhance(img_np, outscale=outscale)
    return output


def upscale_swinir(img_np):
    """Run SwinIR inference with tile support for large images."""
    model = get_model("swinir-psnr")
    device = next(model.parameters()).device
    window_size = model.window_size  # 8
    scale = 4
    tile_size = min(TILE, 512)  # SwinIR-L needs smaller tiles than Real-ESRGAN
    tile_overlap = 32

    # Convert to tensor: HWC [0,255] -> NCHW [0,1]
    img_tensor = torch.from_numpy(img_np).float().permute(2, 0, 1).unsqueeze(0) / 255.0
    img_tensor = img_tensor.to(device)
    _, _, h, w = img_tensor.shape

    with torch.no_grad():
        if h <= tile_size and w <= tile_size:
            output = model(img_tensor)
        else:
            # Tile-by-tile with overlapping weighted blending (official approach)
            sf = scale
            tile = tile_size
            stride = tile - tile_overlap
            h_idx_list = list(range(0, h - tile, stride)) + [h - tile]
            w_idx_list = list(range(0, w - tile, stride)) + [w - tile]
            E = torch.zeros(1, 3, h * sf, w * sf).type_as(img_tensor)
            W = torch.zeros_like(E)

            for h_idx in h_idx_list:
                for w_idx in w_idx_list:
                    in_patch = img_tensor[..., h_idx : h_idx + tile, w_idx : w_idx + tile]
                    out_patch = model(in_patch)
                    out_patch_mask = torch.ones_like(out_patch)
                    E[
                        ...,
                        h_idx * sf : (h_idx + tile) * sf,
                        w_idx * sf : (w_idx + tile) * sf,
                    ].add_(out_patch)
                    W[
                        ...,
                        h_idx * sf : (h_idx + tile) * sf,
                        w_idx * sf : (w_idx + tile) * sf,
                    ].add_(out_patch_mask)
            output = E.div_(W)

    # Convert back: NCHW [0,1] -> HWC [0,255] uint8
    output = output.squeeze(0).clamp(0, 1).cpu()
    output = (output.permute(1, 2, 0).numpy() * 255.0).round().astype(np.uint8)
    return output


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/models")
async def list_models():
    """Return available models with their descriptions."""
    return {
        "default": DEFAULT_MODEL,
        "models": {
            key: {"display": info["display"], "scale": info["scale"]}
            for key, info in MODEL_REGISTRY.items()
        },
    }


@app.post("/upscale")
async def upscale(
    file: UploadFile = File(...),
    model: str = Form(default=DEFAULT_MODEL),
):
    if model not in MODEL_REGISTRY:
        valid = ", ".join(MODEL_REGISTRY.keys())
        return Response(
            content=f"Unknown model: {model}. Valid: {valid}",
            status_code=400,
        )

    backend = MODEL_REGISTRY[model]["backend"]
    scale = MODEL_REGISTRY[model]["scale"]

    image_data = await file.read()
    img = Image.open(io.BytesIO(image_data)).convert("RGB")
    img_np = np.array(img)

    if backend == "realesrgan":
        output = upscale_realesrgan(img_np, model, outscale=scale)
    elif backend == "swinir":
        output = upscale_swinir(img_np)

    result = Image.fromarray(output)
    buf = io.BytesIO()
    result.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "default_model": DEFAULT_MODEL,
        "gpu": torch.cuda.is_available(),
    }
