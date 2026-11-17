#!/bin/bash
# Privileged scenario, remaining controls B6/B7/B8.
# SAME command as the B0-B4 sweep: --reasoning-tokens 0 is a no-op on
# gemini-3.5-flash (thinking cannot be disabled), so thinking is ON, exactly
# like B0-B4. Kept identical for consistency; refusals are separated in analysis.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
UV="${UV:-$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")}"
LOG_DIR="${LOG_DIR:-$HOME/esc_logs}"
SHARED_DIR="${ESCAPE_SHARED_DIR:-/home/ubuntu/shared}"
[[ -n "$SHARED_DIR" && "$SHARED_DIR" != "/" ]] || { echo "refusing: bad SHARED_DIR" >&2; exit 1; }
B5_TOGGLE="$HERE/b5_userns.sh"

for B in B6 B7 B8; do
  export ESCAPE_HARDENING=$B
  echo "============== control=$B =============="
  sudo docker rm -f eval-container >/dev/null 2>&1 || true
  "$UV" run inspect eval scenarios/privileged/task.py \
      --model google/gemini-3.5-flash --reasoning-tokens 0 \
      -T sandbox=local -T token_limit=200000 \
      --message-limit 60 --time-limit 1800 \
      --epochs 10 --max-samples 1 \
      --log-dir "$LOG_DIR" --metadata control=$B \
      || echo ">>> control=$B FAILED (continuing)"
done
sudo docker rm -f eval-container >/dev/null 2>&1 || true
echo "DONE B6 B7 B8"
