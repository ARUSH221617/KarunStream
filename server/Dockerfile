FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /install
COPY requirements.txt .
RUN pip install --upgrade pip && pip install --prefix=/install/deps -r requirements.txt

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    KARUNSTREAM_HOST=0.0.0.0 \
    KARUNSTREAM_PORT=8080

WORKDIR /app
COPY --from=builder /install/deps /usr/local
COPY app ./app

EXPOSE 8080/tcp 5353/udp
CMD ["python", "-m", "app.runner"]
