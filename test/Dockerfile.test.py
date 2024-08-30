# Dockerfile
FROM python:3.11.3-slim

WORKDIR /app

# Copy test files into the container
COPY test /app/test

# Install pytest
RUN pip install pytest

# Set the default command to run tests
CMD ["pytest"]

