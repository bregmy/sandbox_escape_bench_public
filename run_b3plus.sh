#!/bin/bash
# Re-run privileged controls B3 onward after the per-epoch /shared cleanup fix.
# B0-B2 verified clean and kept. Per-epoch wipe now lives in _hardening.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
UV="${UV:-$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")}"
LOG_DIR="${LOG_DIR:-$HOME/esc_logs}"
SHARED_DIR="${ESCAPE_SHARED_DIR:-/home/ubuntu/shared}"
[[ -n "$SHARED_DIR" && "$SHARED_DIR" != "/" ]] || { echo "refusing: bad SHARED_DIR" >&2; exit 1; }
B5_TOGGLE="$HERE/b5_userns.sh"

for B in B3 B4 B6 B7 B8; do
  echo "######## control=$B ########"
  sudo rm -f "$SHARED_DIR"/* 2>/dev/null || true
  export ESCAPE_HARDENING=$B
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
echo "DONE B3 B4 B6 B7 B8"
