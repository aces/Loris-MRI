# syntax=docker/dockerfile:1

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cpanminus \
        libmariadb-dev \
        libmariadb-dev-compat \
        perl

COPY install/requirements/cpanfile /build/cpanfile
COPY install/Digest-BLAKE2-0.02.tar.gz /build/Digest-BLAKE2-0.02.tar.gz

# A self-contained local::lib can be copied without bringing the compiler or CPAN cache into the
# runtime image. DBD::mysql and Digest::BLAKE2 contain native code, so this builder intentionally
# uses the same Debian release and architecture as the runtime image.
RUN cpanm --local-lib-contained /opt/loris-perl --installdeps /build
RUN cpanm --local-lib-contained /opt/loris-perl /build/Digest-BLAKE2-0.02.tar.gz
