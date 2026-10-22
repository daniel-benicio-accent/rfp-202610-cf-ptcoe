FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE ${PORT}

# One worker, several threads. The MVP used two workers; a single worker keeps
# the FR-9 arrival counter to one per instance instead of one per process,
# which is what makes the demo number readable. Cloud Run gives each instance a
# single vCPU, so two workers bought little anyway.
CMD exec gunicorn --bind 0.0.0.0:${PORT} --workers 1 --threads 8 --timeout 120 main:app
