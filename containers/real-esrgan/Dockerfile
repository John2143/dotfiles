FROM rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0


# Install system deps for OpenCV
RUN apt-get update && apt-get install -y libgl1 libxcb1 && rm -rf /var/lib/apt/lists/*

# Install Real-ESRGAN with API dependencies.
RUN pip install --no-cache-dir realesrgan fastapi uvicorn python-multipart pillow

COPY download_weights.py /tmp/download_weights.py
RUN python /tmp/download_weights.py

WORKDIR /app
COPY server.py .

EXPOSE 7870
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "7870"]
