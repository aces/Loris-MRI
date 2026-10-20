# syntax=docker/dockerfile:1

FROM python:3.11-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        dcmtk \
        dcm2niix \
        imagemagick \
        libmariadb3 \
        mariadb-client \
        perl \
    && rm -rf /var/lib/apt/lists/*

# These named contexts are built from the small, purpose-specific Dockerfiles in test/docker.
# The MINC context exports an empty /opt/minc directory unless INCLUDE_MINC is enabled.
COPY --from=minc /opt/minc /opt/minc
COPY --from=perl /opt/loris-perl /opt/loris-perl
COPY --from=python /opt/loris-venv /opt/loris-venv

# Get the database credentials as parameters
ARG DATABASE_NAME
ARG DATABASE_USER
ARG DATABASE_PASS

# Install LORIS-MRI Python
WORKDIR /opt/loris/bin/mri
COPY . .

# Keep the standard LORIS environment script usable while storing the copied virtual environment
# outside the source tree.
RUN ln -s /opt/loris-venv .venv

# Run the test LORIS-MRI installer
RUN bash ./test/imaging_install_test.sh "$DATABASE_NAME" "$DATABASE_USER" "$DATABASE_PASS"

ENTRYPOINT ["./test/entrypoint.sh"]
