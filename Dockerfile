#Stage1
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN python -m venv /opt/venv
COPY requirements.txt .
RUN /opt/venv/bin/pip install --no-cache-dir -r requirements.txt 

#Stage2
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app.py .
COPY templates ./templates
COPY model ./model

RUN useradd -m appuser && chown -R appuser /app
USER appuser

EXPOSE 6000

CMD ["/opt/venv/bin/gunicorn", "--bind", "0.0.0.0:6000", "app:app"]
