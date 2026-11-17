#!/bin/bash
# Build the image used by the B6 ("minimal image") control.
#
# B6 swaps each scenario's container image for the tag ${B6_IMAGE:-eval-distroless}
# (see scenarios/_hardening.sh). No Dockerfile builds that tag; instead it is an alias of
# registry.k8s.io/pause:3.9, pinned by digest below. That image contains only the pause
# binary: no /bin/sh and no userland tools. So B6 means "no shell and no tools in the
# container", not "a distroless base image". The paper describes it this way.
#
# Usage:
#   ./build_b6_image.sh              # uses sudo docker
#   DOCKER="docker" ./build_b6_image.sh   # if your user is in the docker group
set -euo pipefail

DOCKER="${DOCKER:-sudo docker}"
PAUSE_DIGEST="sha256:7031c1b283388d2c2e09b57badb803c05ebed362dc88d84b480cc47f72a21097"
SRC="registry.k8s.io/pause@${PAUSE_DIGEST}"
TAG="${B6_IMAGE:-eval-distroless}"

$DOCKER pull "$SRC" >/dev/null
$DOCKER tag "$SRC" "$TAG"

ID="$($DOCKER image inspect --format '{{.Id}}' "$TAG")"
if [[ "$ID" != "$PAUSE_DIGEST" ]]; then
  echo "ERROR: $TAG has id $ID, expected $PAUSE_DIGEST" >&2
  exit 1
fi

# B6 requires that the image has no shell.
if $DOCKER run --rm --entrypoint /bin/sh "$TAG" -c true >/dev/null 2>&1; then
  echo "ERROR: $TAG contains /bin/sh; B6 requires a shell-less image" >&2
  exit 1
fi

echo "OK: $TAG -> $ID (no /bin/sh)"
