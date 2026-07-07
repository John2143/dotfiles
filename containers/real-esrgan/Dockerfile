FROM rocm/pytorch:latest

# Install system deps for OpenCV
RUN apt-get update && apt-get install -y libgl1 libxcb1 && rm -rf /var/lib/apt/lists/*

# Install Real-ESRGAN with API dependencies.
# Pin basicsr from git master for torchvision 0.25 compatibility
# (functional_tensor was removed in newer torchvision, basicsr 1.4.2 still needs it).
RUN pip install --no-cache-dir realesrgan fastapi uvicorn python-multipart pillow && \
    pip install --no-cache-dir git+https://github.com/xinntao/BasicSR.git

COPY download_weights.py /tmp/download_weights.py
RUN python /tmp/download_weights.py

WORKDIR /app
COPY server.py .

EXPOSE 7870
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "7870"]
