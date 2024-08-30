# Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY . /app

RUN pip install pytest

CMD ["pytest"]
