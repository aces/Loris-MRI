# syntax=docker/dockerfile:1

FROM python:3.11-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libmariadb-dev \
        libmariadb-dev-compat \
        pkg-config

WORKDIR /opt/loris/bin/mri
COPY . .

# Keep the virtual environment at the same absolute location used by the runtime image. Editable
# installs record source paths, so the repository also uses the same WORKDIR in both images.
RUN python -m venv /opt/loris-venv \
    && pip_install() { \
        attempt=1; \
        while ! /opt/loris-venv/bin/pip install --no-cache-dir "$@"; do \
            if [ "$attempt" -ge 3 ]; then return 1; fi; \
            echo "pip install failed; retrying ($attempt/3)..." >&2; \
            attempt=$((attempt + 1)); \
        done; \
    }; \
    pip_install --editable ".[test]" \
    && for pyproject in python/loris_*/pyproject.toml; do \
        package="${pyproject%/pyproject.toml}"; \
        pip_install --no-deps --editable "$package"; \
    done
