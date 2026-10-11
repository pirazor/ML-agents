# Official python image via AWS's public mirror of Docker Hub (avoids Docker Hub pull rate limits)
FROM public.ecr.aws/docker/library/python:3.12-slim

RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user PATH=/home/user/.local/bin:$PATH HF_HOME=/home/user/.cache/huggingface
WORKDIR /home/user/app

COPY --chown=user requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Bake the weights into the image so restarts don't re-download 1.9 GB
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('fastino/GLiNER2.5-Decide')"
ENV HF_HUB_OFFLINE=1

COPY --chown=user app.py .
EXPOSE 7860
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
