# syntax=docker/dockerfile:1

FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libmariadb-dev \
        libmariadb-dev-compat \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/loris/bin/mri

# Copy project metadata first so code changes do not invalidate the external dependency layer.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --extra test --no-install-workspace

# Copy the repository and install the workspace.
COPY . .
RUN uv sync --locked --no-dev --extra test
