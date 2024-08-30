# Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY ./hello-world-pytest /app

RUN pip install pytest

CMD ["pytest"]
