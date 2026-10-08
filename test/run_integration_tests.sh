#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AWS_CLI_IMAGE="amazon/aws-cli:2.17.57"

source "$SCRIPT_DIR/loris-data.env"

loris_ref="${LORIS_REF:-main}"
data_dir="${LORIS_TEST_DATA:-}"
cache_dir="${LORIS_TEST_CACHE:-${HOME}/.cache/loris/test}"
loris_dir=""
compose=(docker compose --file "$SCRIPT_DIR/docker-compose.yml")

# CI adds a cache backend through an override while local builds use Docker's persistent layer
# cache. Keeping this selection outside the base Compose file makes the default command portable.
if [[ -n "${LORIS_TEST_COMPOSE_OVERRIDE:-}" ]]; then
    compose+=(--file "$LORIS_TEST_COMPOSE_OVERRIDE")
fi

usage() {
    cat <<'EOF'
Usage: test/run_integration_tests.sh [OPTIONS]

Build and run the LORIS-MRI integration tests in Docker.

Options:
  --loris-ref REF   LORIS core branch, tag, or commit to test against (default: main)
  --data-dir PATH   Existing imaging test dataset (otherwise downloaded and cached)
  --cache-dir PATH  Cache directory (default: ~/.cache/loris/test)
  -h, --help        Show this help

Environment equivalents:
  LORIS_REF, LORIS_TEST_DATA, LORIS_TEST_CACHE
EOF
}

parse_arguments() {
    while (($#)); do
        case "$1" in
            --loris-ref)
                [[ $# -ge 2 ]] || { echo "ERROR: --loris-ref requires a value" >&2; exit 2; }
                loris_ref="$2"
                shift 2
                ;;
            --data-dir)
                [[ $# -ge 2 ]] || { echo "ERROR: --data-dir requires a value" >&2; exit 2; }
                data_dir="$2"
                shift 2
                ;;
            --cache-dir)
                [[ $# -ge 2 ]] || { echo "ERROR: --cache-dir requires a value" >&2; exit 2; }
                cache_dir="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done
}

check_requirements() {
    command -v git >/dev/null || { echo "ERROR: Git is required." >&2; exit 1; }
    command -v docker >/dev/null || { echo "ERROR: Docker is required." >&2; exit 1; }
    docker compose version >/dev/null || { echo "ERROR: Docker Compose v2 is required." >&2; exit 1; }
}

# LORIS-MRI integration tests only need the core LORIS schema and Raisinbread seed data. Using a
# sparse checkout avoids downloading unused files to save resources.
prepare_loris_checkout() {
    mkdir -p "$cache_dir"
    cache_dir="$(cd "$cache_dir" && pwd)"
    loris_dir="$cache_dir/loris-ref"

    if [[ ! -d "$loris_dir/.git" ]]; then
        echo "Cloning LORIS core..."
        git clone --depth 1 --filter=blob:none --no-checkout --sparse \
            https://github.com/aces/loris.git "$loris_dir"
    fi

    git -C "$loris_dir" sparse-checkout set \
        SQL \
        raisinbread/instruments/instrument_sql \
        raisinbread/RB_files
    echo "Fetching LORIS core ref '$loris_ref'..."
    git -C "$loris_dir" fetch --depth 1 origin "$loris_ref"
    git -C "$loris_dir" checkout --detach --force FETCH_HEAD
    echo "Using LORIS core commit $(git -C "$loris_dir" rev-parse HEAD)"
}

# Use an AWS CLI container so synchronizing fixtures does not add an AWS CLI installation
# requirement to developer machines. The cache belongs exclusively to this script, so `--delete`
# can keep it identical to the bucket. Even though the DICOM study contains many files, unchanged
# objects require only metadata comparisons and are not downloaded again.
sync_test_dataset() {
    data_dir="$cache_dir/loris-data"
    mkdir -p "$data_dir"
    echo "Synchronizing the imaging test dataset at $data_dir..."
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        --env HOME=/tmp \
        --env AWS_ACCESS_KEY_ID="$BUCKET_ACCESS_KEY" \
        --env AWS_SECRET_ACCESS_KEY="$BUCKET_SECRET_KEY" \
        --env AWS_EC2_METADATA_DISABLED=true \
        --volume "$data_dir:/data" \
        "$AWS_CLI_IMAGE" \
        s3 sync "s3://${BUCKET_NAME:-loris-rb-data}" /data \
        --endpoint-url "${BUCKET_URL:-https://ace-minio-1.loris.ca:9000}" \
        --delete \
        --no-progress
}

prepare_test_dataset() {
    if [[ -z "$data_dir" ]]; then
        sync_test_dataset
    fi

    [[ -d "$data_dir" ]] || {
        echo "ERROR: Imaging test dataset does not exist: $data_dir" >&2
        exit 1
    }
    data_dir="$(cd "$data_dir" && pwd)"
}

configure_compose() {
    export LORIS_CORE_DIR="$loris_dir"
    export LORIS_TEST_DATA="$data_dir"
    export COMPOSE_PROJECT_NAME="loris-mri-integration-${UID}"
}

# Integration tests modify both the database and the generated imaging tree. Always removing the
# Compose project gives every invocation pristine state without discarding reusable image layers or
# the read-only source dataset.
cleanup() {
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

build_images() {
    echo "Building integration test images..."
    "${compose[@]}" build
}

run_tests() {
    echo "Running integration tests..."
    "${compose[@]}" run --rm mri pytest python/tests/integration
}

main() {
    parse_arguments "$@"
    check_requirements
    prepare_loris_checkout
    prepare_test_dataset
    configure_compose

    # Also clear state left by a previously interrupted invocation before starting this one.
    cleanup
    build_images
    run_tests
}

main "$@"
