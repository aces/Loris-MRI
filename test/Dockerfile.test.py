# Dockerfile
FROM python:3.11.3-slim

WORKDIR /app

# Install pytest
RUN pip install pytest

# Set the default command to run tests
CMD ["pytest"]

