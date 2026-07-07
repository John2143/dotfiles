FROM rocm/pytorch:latest

# Install Real-ESRGAN with API dependencies (torch is already in the base)
RUN pip install --no-cache-dir realesrgan fastapi uvicorn python-multipart pillow

COPY download_weights.py /tmp/download_weights.py
RUN python /tmp/download_weights.py

WORKDIR /app
COPY server.py .

EXPOSE 7870
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "7870"]
