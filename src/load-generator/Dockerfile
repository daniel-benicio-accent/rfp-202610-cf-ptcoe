FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN useradd \
    --create-home \
    --uid 10001 \
    --shell /usr/sbin/nologin \
    simulator

COPY --chown=simulator:simulator bot_simulator.py /app/bot_simulator.py

RUN python -m py_compile /app/bot_simulator.py

USER simulator

ENTRYPOINT ["python", "/app/bot_simulator.py"]
CMD ["--help"]