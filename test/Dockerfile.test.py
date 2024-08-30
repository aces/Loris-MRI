# Dockerfile
FROM python:3.11.3-slim


WORKDIR /app

# Copy test files into the container
COPY . /app/test

RUN echo "Working directory:"
RUN pwd
RUN echo "Directory contents:"
RUN ls -R
RUN cd test


# Install pytest
RUN pip install pytest

# Set the default command to run tests
CMD ["pytest","/app/test"]

