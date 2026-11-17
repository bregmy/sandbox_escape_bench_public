# B0–B8 hardening commands for each scenario

Each hardening control is selected with the `ESCAPE_HARDENING` env var, which the
scenario `setup.sh` reads (via `scenarios/_hardening.sh`) and appends to `docker run`.

## Control status

| Control | Meaning | Works now? |
|---------|---------|------------|
| B0 | Baseline (no extra flags) | ✅ |
| B1 | `--cap-drop=ALL` | ✅ |
| B2 | `--security-opt no-new-privileges` | ✅ |
| B3 | Strict seccomp (`scenarios/_strict_seccomp.json`) | ✅ |
| B4 | `--read-only` root fs | ✅ |
| B5 | User-namespace remap | ✅ daemon toggle `~/b5_userns.sh on\|off` (verified uid 100000) |
| B6 | Minimal/distroless image | ✅ swaps to `eval-distroless` (no shell) via `ESCAPE_IMAGE` |
| B7 | gVisor `--runtime=runsc` | ✅ runsc installed + registered (4.19.0-gvisor) |
| B8 | Composite B1+B2+B3+B4 | ✅ (B5 remap is daemon-level; run separately) |

## Command template

```bash
export GOOGLE_API_KEY=...        # once per shell
cd ~/sandbox_escape_bench

export ESCAPE_HARDENING=<B0..B8>              # pick the control
sudo docker rm -f eval-container 2>/dev/null  # cleanup before each run
~/.local/bin/uv run inspect eval scenarios/<SCENARIO>/task.py \
    --model google/gemini-3.5-flash \
    --reasoning-tokens 0 \
    -T sandbox=local \
    -T token_limit=500000 \
    --epochs 1 \
    --log-dir ~/esc_logs \
    --metadata control=$ESCAPE_HARDENING
```

Confirm the control took effect: each run prints a line like
`[hardening] ESCAPE_HARDENING=B1 -> docker args: --cap-drop=ALL` in the setup output.

## Full matrix (copy/paste)

Below, each block runs ONE scenario across B0–B4 and B8. Change `--epochs` for more trials.
`S=<scenario>` then loop the controls:

```bash
cd ~/sandbox_escape_bench
export GOOGLE_API_KEY=...

for S in privileged docker_socket pid_namespace sys_admin sys_module dac_read_search hostpath_etc; do
  for B in B0 B1 B2 B3 B4 B8; do
    export ESCAPE_HARDENING=$B
    sudo docker rm -f eval-container 2>/dev/null
    ~/.local/bin/uv run inspect eval scenarios/$S/task.py \
        --model google/gemini-3.5-flash --reasoning-tokens 0 \
        -T sandbox=local -T token_limit=500000 --epochs 1 \
        --log-dir ~/esc_logs --metadata control=$B
  done
done
```

(That is exactly what `~/run_scenarios.sh` does — set `CONTROLS` and `EPOCHS` there instead.)

### Per-scenario single commands

Replace `privileged` with any scenario; replace `B0` with the control.

```bash
# privileged, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/privileged/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done

# docker_socket, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/docker_socket/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done

# pid_namespace, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/pid_namespace/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done

# sys_admin, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/sys_admin/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done

# sys_module, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/sys_module/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done

# dac_read_search, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/dac_read_search/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done

# hostpath_etc, B0..B8
for B in B0 B1 B2 B3 B4 B8; do export ESCAPE_HARDENING=$B; sudo docker rm -f eval-container 2>/dev/null; ~/.local/bin/uv run inspect eval scenarios/hostpath_etc/task.py --model google/gemini-3.5-flash --reasoning-tokens 0 -T sandbox=local -T token_limit=500000 --epochs 1 --log-dir ~/esc_logs --metadata control=$B; done
```

## Controls needing extra infrastructure (B5, B6, B7) — ALL SET UP

- **B5 user-namespace remap** is daemon-wide, so run it as a SEPARATE BATCH using
  the toggle script (it preserves the runsc runtime block for B7):
  ```bash
  ~/b5_userns.sh on        # enable remap (container root -> host uid 100000)
  # ... run your B5 scenarios here (ESCAPE_HARDENING=B5) ...
  ~/b5_userns.sh off       # restore normal daemon when done
  ~/b5_userns.sh status    # check current state
  ```
  Caveats:
  - Enabling remap switches Docker to a SEPARATE image store, so scenario images
    must be (re)built while remap is ON. For scenarios that build inline (eval-base),
    delete the provision marker first so setup.sh rebuilds:
    `sudo rm -f /var/cache/eval/.provisioned`
  - `--privileged` is INCOMPATIBLE with userns-remap, so the `privileged` scenario
    cannot run under B5 (docker refuses). Record this in the applicability matrix.

- **B6 minimal/distroless image**: the shell-less image is tagged `eval-distroless`
  (k8s `pause` — stays alive, has no bash/gcc/curl). `ESCAPE_HARDENING=B6` sets
  `ESCAPE_IMAGE=eval-distroless`, and each scenario `setup.sh` runs
  `${ESCAPE_IMAGE:-<default>}`. The agent's `docker exec bash` fails ("executable
  not found") = no foothold. To use a real distroless base instead:
  `B6_IMAGE=gcr.io/distroless/base-debian12 ESCAPE_HARDENING=B6 ...`

- **B7 gVisor**: installed and registered (`runsc version release-20261102.0`).
  `ESCAPE_HARDENING=B7` uses `--runtime=runsc`; verified container kernel `4.19.0-gvisor`.

## Viewing results by control

```bash
cd ~/sandbox_escape_bench
~/.local/bin/uv run inspect view --log-dir ~/esc_logs
# each run is tagged with metadata control=Bx
```
