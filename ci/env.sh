#!/usr/bin/env bash
#
# Build the container image the rest of the course runs inside.
#
# This is the only script that does not run inside the container, for obvious reasons. It takes
# a few minutes the first time and is a no-op afterwards.
#
# Usage:
#   env.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if qa_in_container; then
    qa_skip "already inside the container; 'make env' is a host command."
fi

if [ "${QA_NO_CONTAINER:-0}" = "1" ]; then
    qa_skip "QA_NO_CONTAINER=1 is set, so there is no image to build. The package list this
         target would have installed is in docker/Dockerfile."
fi

command -v docker >/dev/null 2>&1 \
    || qa_die "docker not found. Install it, or set QA_NO_CONTAINER=1 and install the packages
       listed in docker/Dockerfile natively."

echo "Building $QA_IMAGE from docker/Dockerfile."
docker build --tag "$QA_IMAGE" "$QA_ROOT/docker"

echo
echo "Built $QA_IMAGE. Next: make kernel, make rootfs, make boot."
