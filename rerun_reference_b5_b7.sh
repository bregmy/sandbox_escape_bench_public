#!/bin/bash
# Re-run the reference-exploit verifier for controls B5, B6 and B7, recording every command.
#
# Output directory (default: results/reference_rerun/; must not already contain a CSV):
#   reference_exploits.csv   same schema as results/eval_logs/reference_exploits.csv
#   rerun_commands.txt       every command executed, with timestamps and exit codes
#   rerun_environment.txt    docker, runsc (incl. sha512), kernel, git commit, script checksums
#   verify_<control>.log     full output of verify_exploits.sh for each control
#   userns_toggle.log        output of b5_userns.sh on/off
#   host_etc_check.txt       before/after check of host /etc/crontab (hostpath reference exploit writes it)
#
# Passes:
#   1. B5: userns-remap ON -> verify (CONTROLS=B5) -> userns-remap OFF (also on error/exit)
#   2. B6: build_b6_image.sh -> verify (CONTROLS=B6)
#   3. B7: verify (CONTROLS=B7); gVisor runsc must already be registered
#
# Expected by design: privileged and pid_namespace under B5 ERR (Docker refuses
# --privileged and host-PID with userns-remap). B5 and B7 may vary between sessions.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
OUT="${OUT:-$HERE/results/reference_rerun}"
export SCENARIOS="${SCENARIOS:-privileged docker_socket pid_namespace sys_admin sys_module dac_read_search hostpath_etc}"
export ESCAPE_SHARED_DIR="${ESCAPE_SHARED_DIR:-/home/ubuntu/shared}"
export LOG_DIR="$OUT"
export REPEATS=1

mkdir -p "$OUT"
if [[ -e "$OUT/reference_exploits.csv" ]]; then
  echo "refusing: $OUT/reference_exploits.csv already exists; choose an empty OUT" >&2
  exit 1
fi
CMDS="$OUT/rerun_commands.txt"
ENVF="$OUT/rerun_environment.txt"
SNAP="$OUT/host_etc_snapshot"
USERNS_ON=0

log_cmd() { echo "$(date -Iseconds) $*" | tee -a "$CMDS" >&2; }

record_env() {
  {
    echo "date: $(date -Iseconds)"
    echo "host kernel: $(uname -r)"
    echo "docker server: $(sudo docker version --format '{{.Server.Version}}' 2>/dev/null)"
    echo "runsc: $(/usr/bin/runsc --version 2>/dev/null | head -1)"
    echo "runsc path: /usr/bin/runsc"
    echo "runsc sha512: $(sha512sum /usr/bin/runsc 2>/dev/null | cut -d' ' -f1)"
    echo "uv: $("$HOME/.local/bin/uv" --version 2>/dev/null || uv --version 2>/dev/null)"
    echo "git commit: $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo 'not a git checkout')"
    echo "verify_exploits.sh sha256: $(sha256sum verify_exploits.sh | cut -d' ' -f1)"
    echo "scenarios/_hardening.sh sha256: $(sha256sum scenarios/_hardening.sh | cut -d' ' -f1)"
    echo "build_b6_image.sh sha256: $(sha256sum build_b6_image.sh | cut -d' ' -f1)"
    echo "b5_userns.sh sha256: $(sha256sum b5_userns.sh | cut -d' ' -f1)"
    echo "SCENARIOS: $SCENARIOS"
    echo "ESCAPE_SHARED_DIR: $ESCAPE_SHARED_DIR"
    echo "userns-remap now: $(sudo docker info 2>/dev/null | grep -qi userns && echo ON || echo OFF)"
  } > "$ENVF"
}

userns_set() {  # $1 = on|off
  log_cmd "./b5_userns.sh $1"
  ./b5_userns.sh "$1" >> "$OUT/userns_toggle.log" 2>&1
  local rc=$?
  log_cmd "  -> rc=$rc"
  return $rc
}

restore_userns() {
  if [[ "$USERNS_ON" == 1 ]]; then
    userns_set off
    USERNS_ON=0
  fi
}
trap restore_userns EXIT

verify_control() {  # $1 = control
  local ctrl="$1"
  log_cmd "CONTROLS=$ctrl REPEATS=1 LOG_DIR=$OUT SCENARIOS=\"$SCENARIOS\" ./verify_exploits.sh > verify_$ctrl.log"
  CONTROLS="$ctrl" ./verify_exploits.sh > "$OUT/verify_$ctrl.log" 2>&1
  local rc=$?
  log_cmd "  -> rc=$rc"
}

snapshot_host_etc() {
  mkdir -p "$SNAP"
  sudo cp -a /etc/crontab "$SNAP/crontab" 2>/dev/null || true
  sudo cp -a /etc/cron.d "$SNAP/" 2>/dev/null || true
  sha256sum /etc/crontab 2>/dev/null > "$SNAP/crontab.sha256"
}

check_host_etc() {
  {
    echo "== host /etc/crontab after rerun =="
    sha256sum /etc/crontab 2>/dev/null
    echo "== snapshot =="
    cat "$SNAP/crontab.sha256" 2>/dev/null
    if sudo grep -q 'flag' /etc/crontab 2>/dev/null; then
      echo "NOTE: /etc/crontab contains 'flag' after the rerun; restoring from snapshot"
      sudo cp -a "$SNAP/crontab" /etc/crontab
      echo "restored: $(sha256sum /etc/crontab | cut -d' ' -f1)"
    else
      echo "OK: /etc/crontab has no flag entry"
    fi
  } > "$OUT/host_etc_check.txt"
  log_cmd "host /etc/crontab check written to host_etc_check.txt"
}

touch "$CMDS"
log_cmd "# rerun start: OUT=$OUT SCENARIOS=\"$SCENARIOS\" ESCAPE_SHARED_DIR=$ESCAPE_SHARED_DIR"
record_env
snapshot_host_etc

# ---- pass 1: B5 ----
userns_set on
if sudo docker info 2>/dev/null | grep -qi userns; then
  USERNS_ON=1
  verify_control B5
  restore_userns
else
  log_cmd "ERROR: userns-remap did not turn on; skipping B5"
fi

# ---- pass 2: B6 ----
log_cmd "./build_b6_image.sh"
./build_b6_image.sh >> "$OUT/b6_image.log" 2>&1
log_cmd "  -> rc=$?"
verify_control B6

# ---- pass 3: B7 ----
verify_control B7

check_host_etc
record_env
log_cmd "# rerun end"

echo
echo "Rerun complete. CSV: $OUT/reference_exploits.csv"
echo "Commands: $CMDS"
