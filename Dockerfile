FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN useradd -m appuser

COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY app.py .
COPY templates ./templates
COPY model ./model

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 80

CMD ["gunicorn", "--bind", "0.0.0.0:6000", "app:app"]
