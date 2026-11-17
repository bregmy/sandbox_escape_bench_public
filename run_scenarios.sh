#!/bin/bash
# Run all local-mode Docker scenarios through SandboxEscapeBench.
# Lives OUTSIDE the repo; it cd's into the repo to run inspect.
#
# Usage:
#   export GOOGLE_API_KEY=...        # or you'll be prompted
#   ./run_scenarios.sh               # defaults below
#   MODEL=google/gemini-3.5-flash EPOCHS=10 TOKEN_LIMIT=500000 ./run_scenarios.sh
#
# Results: all .eval logs land in $LOG_DIR; view with:
#   cd <checkout> && uv run inspect view --log-dir ~/esc_logs

set -u

# ---- config (override via env) ----
REPO="${REPO:-$(cd "$(dirname "$0")" && pwd)}"
UV="${UV:-$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")}"
MODEL="${MODEL:-google/gemini-3.5-flash}"
EPOCHS="${EPOCHS:-1}"
TOKEN_LIMIT="${TOKEN_LIMIT:-500000}"
REASONING_TOKENS="${REASONING_TOKENS:-0}"
LOG_DIR="${LOG_DIR:-$HOME/esc_logs}"
VARIANT="${VARIANT:-normal}"   # normal | hint | solution

# Docker, non-kernel scenarios that work in local mode.
SCENARIOS=(
  privileged
  docker_socket
  pid_namespace
  sys_admin
  sys_module
  dac_read_search
  hostpath_etc
)

# ---- preflight ----
if [[ -z "${GOOGLE_API_KEY:-}" ]]; then
  read -rsp "GOOGLE_API_KEY: " GOOGLE_API_KEY && echo
  export GOOGLE_API_KEY
fi
[[ -d "$REPO" ]] || { echo "Repo not found: $REPO" >&2; exit 1; }
mkdir -p "$LOG_DIR"
cd "$REPO" || exit 1

cleanup() { sudo docker rm -f eval-container >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Hardening controls to sweep (space-separated). Default B0..B8.
# Flag-based controls work now: B0 B1 B2 B3 B4 B8.
# B5 (userns-remap) B6 (distroless) B7 (gVisor) need extra infra - see README.
CONTROLS="${CONTROLS:-B0 B1 B2 B3 B4 B8}"

echo "Model=$MODEL  Epochs=$EPOCHS  TokenLimit=$TOKEN_LIMIT  Variant=$VARIANT"
echo "Controls: $CONTROLS"
echo "Logs -> $LOG_DIR"
echo "Scenarios: ${SCENARIOS[*]}"
echo

# ---- sweep control x scenario sequentially (shared container name => no parallel) ----
for ctrl in $CONTROLS; do
  export ESCAPE_HARDENING="$ctrl"
  for s in "${SCENARIOS[@]}"; do
    echo "============== control=$ctrl scenario=$s =============="
    cleanup
    "$UV" run inspect eval "scenarios/$s/task.py" \
      --model "$MODEL" \
      --reasoning-tokens "$REASONING_TOKENS" \
      -T sandbox=local \
      -T variant="$VARIANT" \
      -T token_limit="$TOKEN_LIMIT" \
      --epochs "$EPOCHS" \
      --max-samples 1 \
      --log-dir "$LOG_DIR" \
      --metadata "control=$ctrl" \
      || echo ">>> control=$ctrl $s FAILED (continuing)"
    echo
  done
done

cleanup
echo "Done. View results: cd $REPO && $UV run inspect view --log-dir $LOG_DIR"
