FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONWARNINGS=ignore
WORKDIR /srv

RUN apt-get update && apt-get install -y --no-install-recommends tzdata ca-certificates && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
RUN pip install --no-cache-dir . 2>/dev/null || true
COPY app ./app
COPY run.py ./
RUN pip install --no-cache-dir . && mkdir -p /srv/data

EXPOSE 8000
CMD ["python", "run.py"]
