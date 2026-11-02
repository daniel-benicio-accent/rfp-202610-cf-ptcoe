FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY bot_simulator.py .

USER 10001:10001
ENTRYPOINT ["python", "/app/bot_simulator.py"]
