# Paper (LaTeX)

Defensive ablation study of container hardening controls against LLM sandbox
escapes. Built with the standard `article` class; retarget the document class in
`main.tex` once a venue is chosen (USENIX Security, IEEE S&P, NDSS, or arXiv).

## Build the PDF on a new machine

The PDF is not committed. Build it from source.

### 1. Install a TeX distribution

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install latexmk texlive-latex-base texlive-latex-recommended \
                 texlive-latex-extra texlive-fonts-recommended
```

macOS: install MacTeX (or `brew install --cask mactex-no-gui`), then make sure
`latexmk` is on your `PATH`.

Windows: install TeX Live or MiKTeX. Enable automatic installation of missing
packages when prompted.

Alternatively, upload the `overleaf/` folder to Overleaf as a new project.
Overleaf provides every package automatically.

### 2. Clone and build

```bash
git clone <repo-url>
cd sandbox_escape_bench/overleaf
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex
```

The output is `main.pdf` in this folder. Rebuild after an edit with the same
command. To remove build artifacts and start clean:

```bash
latexmk -C
```

If `latexmk` is not available, use the classic sequence:

```bash
pdflatex -interaction=nonstopmode main
bibtex main
pdflatex -interaction=nonstopmode main
pdflatex -interaction=nonstopmode main
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `File 'X.sty' not found` | Install the missing package. `tlmgr install X` on TeX Live, or let MiKTeX install it. On Debian/Ubuntu, `apt install texlive-latex-extra` covers `multirow` and `cleveref`. |
| `Citation ... undefined` or `Reference ... undefined` | Run `latexmk -pdf main.tex` again. If it persists, run `latexmk -C` and rebuild. |
| Stale output after an edit | `latexmk -C`, then rebuild. |
| `latexmk: command not found` | Install `latexmk` (see step 1), or use the `pdflatex`/`bibtex` sequence above. |

`main.bbl` is committed so the bibliography also works with `pdflatex` alone.
Re-run `latexmk` after editing `refs.bib` to regenerate it.

## Layout

```
overleaf/
  main.tex              # document skeleton; \input's each section
  refs.bib              # bibliography
  main.bbl              # committed bibliography output (see above)
  sections/             # introduction, related work, methodology, results, discussion, limitations, conclusion
  tables/               # controls, RQ3 scheme, hardening matrix, RQ3 matrix
```

## Data sources

The tables are filled in by hand from the evaluation logs in the repository root,
not generated automatically:

- Model escape rates: `../results/eval_logs/*.eval` (filter by the `control=Bx` metadata).
- Reference-exploit outcomes (RQ3): `../results/eval_logs/reference_exploits.csv`.

Two macros are defined in `main.tex`:

- `\todo{...}`: marks prose still to write. It renders in red, so unfinished text is easy to spot. The body currently has none.
- `\num{...}`: typesets a number from the logs as plain text.
