# syntax=docker/dockerfile:1

# MINC is deprecated and excluded by default. INCLUDE_MINC remains a generic image-composition
# option so this artifact can also be reused outside the integration-test runner.
FROM debian:bookworm-slim

ARG INCLUDE_MINC=false
ARG MINC_PACKAGE_URL=https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian

RUN mkdir -p /opt/minc \
    && case "$INCLUDE_MINC" in \
        false) ;; \
        true) \
            apt-get update; \
            apt-get install -y --no-install-recommends ca-certificates wget; \
            wget -q "${MINC_PACKAGE_URL}/minc-toolkit-1.9.18-20200813-Debian_10-x86_64.deb" -O /tmp/minc-toolkit.deb; \
            wget -q "${MINC_PACKAGE_URL}/minc-toolkit-testsuite-0.1.3-20131212.deb" -O /tmp/minc-toolkit-testsuite.deb; \
            wget -q "${MINC_PACKAGE_URL}/bic-mni-models-0.1.1-20120421.deb" -O /tmp/bic-mni-models.deb; \
            wget -q "${MINC_PACKAGE_URL}/beast-library-1.1.0-20121212.deb" -O /tmp/beast-library.deb; \
            for package in /tmp/*.deb; do dpkg-deb --extract "$package" /; done; \
            rm -rf /tmp/*.deb /var/lib/apt/lists/*; \
            ;; \
        *) echo "INCLUDE_MINC must be 'true' or 'false'" >&2; exit 2 ;; \
    esac
