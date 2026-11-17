#!/bin/bash
# B5 (user-namespace remap) daemon toggle for SandboxEscapeBench.
#
# userns-remap is a DAEMON-WIDE setting, not a per-container flag, so B5 is run
# as a separate batch: turn it ON, run your B5 scenarios, then turn it OFF.
# This script edits /etc/docker/daemon.json WHILE PRESERVING the runsc runtime
# block (needed for B7), then restarts docker.
#
#   ./b5_userns.sh on     # enable remap  (container root -> unprivileged host uid)
#   ./b5_userns.sh off    # disable remap (back to normal; default for B0-B4,B6-B8)
#   ./b5_userns.sh status # show current state
#
# NOTE: userns-remap is INCOMPATIBLE with --privileged. The `privileged` scenario
# cannot run under B5 (docker will refuse). That incompatibility is itself a
# finding for the applicability matrix.
set -euo pipefail

DAEMON=/etc/docker/daemon.json

status() {
  if sudo docker info 2>/dev/null | grep -qi 'userns'; then
    echo "B5 userns-remap: ON"
  else
    echo "B5 userns-remap: OFF"
  fi
  echo "--- $DAEMON ---"; sudo cat "$DAEMON" 2>/dev/null || echo "(none)"
}

set_remap() {
  local want="$1"  # "on" or "off"
  sudo python3 - "$DAEMON" "$want" <<'PY'
import json, sys, os
path, want = sys.argv[1], sys.argv[2]
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        txt = f.read().strip()
        if txt:
            cfg = json.loads(txt)
# Always keep the runsc runtime registered (needed for B7).
cfg.setdefault("runtimes", {})["runsc"] = {"path": "/usr/bin/runsc"}
if want == "on":
    cfg["userns-remap"] = "default"
else:
    cfg.pop("userns-remap", None)
with open(path, "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
print(f"wrote {path}: userns-remap={'default' if want=='on' else '<removed>'}")
PY
  sudo systemctl restart docker
  sleep 2
  status
}

case "${1:-status}" in
  on)  set_remap on ;;
  off) set_remap off ;;
  status) status ;;
  *) echo "usage: $0 {on|off|status}" >&2; exit 2 ;;
esac
