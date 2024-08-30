# Dockerfile
FROM python:3.11.3-slim

WORKDIR /app

COPY test/hello-world-pytest /app/test/hello-world-pytest

RUN pip install pytest

CMD ["pytest","/app/test/hello-world-pytest"]
