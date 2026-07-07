import os
import io
import torch
import numpy as np
from PIL import Image
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import Response
from realesrgan import RealESRGANer
from basicsr.archs.rrdbnet_arch import RRDBNet
from basicsr.utils.download import load_file_from_url

app = FastAPI(title="Real-ESRGAN Upscaler")

MODEL_NAME = os.environ.get("ESRGAN_MODEL", "RealESRGAN_x4plus")
MODEL_URLS = {
    "RealESRGAN_x4plus": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
    "RealESRGAN_x4plus_anime": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus_anime_6B.pth",
    "RealESRGAN_x2plus": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x2plus.pth",
}

MODEL_SCALES = {
    "RealESRGAN_x4plus": 4,
    "RealESRGAN_x4plus_anime": 4,
    "RealESRGAN_x2plus": 2,
}

if MODEL_NAME not in MODEL_URLS:
    raise ValueError(f"Unknown model: {MODEL_NAME}. Choose from: {', '.join(MODEL_URLS.keys())}")

SCALE = MODEL_SCALES[MODEL_NAME]

upsampler = None


def load_model():
    global upsampler
    weights_dir = os.path.expanduser("~/.cache/realesrgan")
    model_url = MODEL_URLS[MODEL_NAME]
    model_filename = os.path.basename(model_url)
    model_path = os.path.join(weights_dir, model_filename)

    if not os.path.exists(model_path):
        os.makedirs(weights_dir, exist_ok=True)
        print(f"Downloading model weights: {model_url}")
        load_file_from_url(url=model_url, model_dir=weights_dir, progress=True)

    model = RRDBNet(
        num_in_ch=3,
        num_out_ch=3,
        num_feat=64,
        num_block=23,
        num_grow_ch=32,
        scale=SCALE,
    )
    use_half = torch.cuda.is_available()
    print(f"GPU available: {torch.cuda.is_available()} (using fp16: {use_half})")
    upsampler = RealESRGANer(
        scale=SCALE,
        model_path=model_path,
        model=model,
        tile=0,
        tile_pad=10,
        pre_pad=0,
        half=use_half,
    )


@app.on_event("startup")
async def startup():
    print(f"Loading Real-ESRGAN model: {MODEL_NAME} ({SCALE}x)")
    load_model()
    print("Model loaded successfully")


@app.post("/upscale")
async def upscale(
    file: UploadFile = File(...),
    scale: int = Form(default=4),
):
    image_data = await file.read()
    img = Image.open(io.BytesIO(image_data)).convert("RGB")
    img_np = np.array(img)

    output, _ = upsampler.enhance(img_np, outscale=scale)

    result = Image.fromarray(output)
    buf = io.BytesIO()
    result.save(buf, format="PNG")
    return Response(content=buf.getvalue(), media_type="image/png")


@app.get("/health")
async def health():
    return {"status": "ok", "model": MODEL_NAME, "scale": SCALE, "gpu": torch.cuda.is_available()}
