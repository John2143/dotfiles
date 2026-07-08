import os
import urllib.request

WEIGHTS_DIR = os.path.expanduser("~/.cache/realesrgan")
os.makedirs(WEIGHTS_DIR, exist_ok=True)

models = [
    # Real-ESRGAN models
    ("RealESRGAN_x4plus.pth", "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"),
    ("RealESRGAN_x4plus_anime_6B.pth", "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth"),
    ("RealESRGAN_x2plus.pth", "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth"),
    # SwinIR PSNR model (fidelity, no hallucination)
    ("003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_PSNR.pth",
     "https://github.com/JingyunLiang/SwinIR/releases/download/v0.0/003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_PSNR.pth"),
]

for name, url in models:
    dest = os.path.join(WEIGHTS_DIR, name)
    if os.path.exists(dest):
        print(f"Already exists: {name}")
        continue
    print(f"Downloading {name}...")
    urllib.request.urlretrieve(url, dest)
    print(f"  done ({os.path.getsize(dest)} bytes)")
