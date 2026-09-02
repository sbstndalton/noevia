FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY agent/ ./agent/
COPY config/ ./config/
COPY scripts/ ./scripts/

RUN useradd -m appuser && mkdir -p /app/data && chown -R appuser:appuser /app
USER appuser

EXPOSE 8010
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8010/api/health', timeout=5)" || exit 1

CMD ["uvicorn", "agent.app:app", "--host", "0.0.0.0", "--port", "8010"]
