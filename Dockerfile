FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent/ ./agent/
COPY config/ ./config/
COPY scripts/ ./scripts/

# Runs as root (Unraid community-container convention) so the ./data bind mount is
# writable regardless of host-side ownership. Isolated bridge network, LAN-only.

EXPOSE 8010
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8010/api/health', timeout=5)" || exit 1

CMD ["uvicorn", "agent.app:app", "--host", "0.0.0.0", "--port", "8010"]
