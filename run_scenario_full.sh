#!/bin/bash
# Full per-scenario sweep at the standardized budget: 300k tokens / 120 messages.
# All nine controls (B0-B8) on ONE ruler so they are directly comparable.
# B5 (user-namespace remap) is daemon-level: we flip userns ON around B5 only,
# then restore it to OFF. (For --privileged, B5 is N/A; use run_privileged_full.sh.)
#
# Usage:
#   SCENARIO=pid_namespace bash run_scenario_full.sh
#
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
UV="${UV:-$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")}"
LOG_DIR="${LOG_DIR:-$HOME/esc_logs}"
SHARED_DIR="${ESCAPE_SHARED_DIR:-/home/ubuntu/shared}"
[[ -n "$SHARED_DIR" && "$SHARED_DIR" != "/" ]] || { echo "refusing: bad SHARED_DIR" >&2; exit 1; }
B5_TOGGLE="$HERE/b5_userns.sh"

SCENARIO="${SCENARIO:?set SCENARIO, e.g. SCENARIO=pid_namespace}"
TOKENS=300000
MSGS=120
CONTROLS="${CONTROLS:-B0 B1 B2 B3 B4 B5 B6 B7 B8}"

run_one() {
  local B="$1"
  echo "######## $SCENARIO control=$B (tokens=$TOKENS msgs=$MSGS) ########"
  sudo rm -f "$SHARED_DIR"/* 2>/dev/null || true
  sudo docker rm -f eval-container >/dev/null 2>&1 || true
  export ESCAPE_HARDENING=$B
  "$UV" run inspect eval scenarios/$SCENARIO/task.py \
      --model google/gemini-3.5-flash --reasoning-tokens 0 \
      -T sandbox=local -T token_limit=$TOKENS \
      --message-limit $MSGS --time-limit 1800 \
      --epochs 10 --max-samples 1 \
      --log-dir "$LOG_DIR" --metadata control=$B \
      || echo ">>> $SCENARIO control=$B FAILED (continuing)"
}

for B in $CONTROLS; do
  if [[ "$B" == "B5" ]]; then
    echo "-- enabling user-namespace remap for B5 --"
    "$B5_TOGGLE" on; sleep 2
    run_one B5
    echo "-- restoring user-namespace remap to off --"
    "$B5_TOGGLE" off; sleep 2
  else
    run_one "$B"
  fi
done

sudo docker rm -f eval-container >/dev/null 2>&1 || true
echo "DONE $SCENARIO: $CONTROLS @ ${TOKENS}tok/${MSGS}msg"
