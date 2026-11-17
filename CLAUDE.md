# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Scripts for building a 3D atlas of tau (and other stain) burden from ex vivo MTL MRI (7T mold MRI + 9.4T hi-res MRI), blockface photographs, and serial histology (NISSL + IHC). There is no build system, test suite, or linter: the code is mostly large Bash pipelines that call external neuroimaging tools, plus helper Python/R scripts. User-facing docs (Sphinx/MyST, published on ReadTheDocs) live in `docs/source/`; `docs/source/recon.md` walks through a full reconstruction for an example specimen.

Build docs locally: `cd docs && pip install -r requirements.txt && make html`.

## Runtime environment

- This repo is meant to be checked out as `$ROOT/scripts` inside a project tree with sibling directories `input/`, `manifest/`, `manual/`, `work/`, `dump/`, `tmp/`, `bin/` (see `docs/source/organize_data_pmacs.md`). Paths throughout the scripts are built from `$ROOT`.
- `common.sh` sources `env.sh` (git-ignored, machine-specific; defines `ROOT` and things like `CURL_SSH_HOST`) either from `$TAU_ATLAS_ROOT/scripts/` or from the script's own directory. It also sets `SDIR`, `MDIR=$ROOT/manifest`, `TMPDIR`, `NSLOTS`/ITK thread count from SLURM/LSF, and `umask 002`.
- External tools assumed on `PATH`: `greedy`, `stack_greedy`, `c3d`, `c2d`, `c3d_affine_tool`, `itksnap-wt`, `Rscript`, `python3`, `gsutil`/`gcloud`, `kubectl`, `curl`. Nothing here can really be executed outside the cluster/data environment.

## Main entry points

All three main scripts use the same dispatch pattern: parse `getopts` flags, then call the shell function named by the first positional argument (`$COMMAND "$@"`). Any function in the file is therefore a callable subcommand; run with no args for usage.

- `recon.sh` (~5700 lines) — the core 3D reconstruction pipeline (MRI registration, blockface recon, histology-to-MRI registration, IHC-to-NISSL matching, density splatting, whole-specimen merging, template building). Flags: `-d` trace, `-B` run in-process instead of submitting cluster jobs, `-s <level>` skip expensive steps whose outputs already exist, `-Q <queue>`.
  - `./recon.sh check_specimen_inputs <id>` / `check_specimen_results <id>` show which inputs/outputs of each stage exist — the usual way to check progress.
- `svs_to_cloud.sh` — histology/blockface processing on GCP: discovering new slides, maintaining per-specimen manifests, launching Kubernetes jobs (preprocessing, NISSL DeepCluster multichannel, WildCat density maps) and rsyncing results back. Talks to the PHAS histology annotation server (`histo.itksnap.org`). Common flags on `*_all` functions: `-D` dry run, `-F` force, `-L` legacy, `-M` skip manifest update.
- `copy_input.sh` — data organization: import blockface from Box (`boxsync.py`), export to GCS, set up manual registration workspaces, populate `$ROOT/input`.

## Architecture conventions in `recon.sh`

- **`set_*_vars` functions define every path.** `set_template_vars`, `set_specimen_vars <id>`, `set_block_vars <id> <block>`, `set_block_stain_vars`, `set_block_density_vars`, `set_ihc_slice_vars`, etc. set global variables naming every input, intermediate, manifest and QC file for that level, and call their parent level's setter. Processing functions call the right setter, then use the variables. When adding a step, add its file paths to the matching setter instead of hard-coding paths in the step. These setters turn off `xtrace` while they run, to keep `-d` output readable.
- **`foo_all` / `foo` pairs.** A `*_all <regex>` function iterates specimens/blocks from manifest files (mainly `$MDIR/blockface_src.txt`, lines of `id block1 block2 ...`) whose id matches the regex, and submits one job per item that re-invokes `recon.sh` with the per-item function. `run_blockwise <fn> [params] <regex>` is the generic helper. Many `_all` functions take stain/model/contrast regexes where `all` means `.*`.
- **Cluster submission** goes through the `pybatch` wrapper → `pybatch.sh`, which auto-detects SLURM / LSF / SGE, names jobs (`-N`), sets memory (`-m`) and waits on name patterns (`-w 'fn_*'`). Job logs go to `$ROOT/dump`. `-B` (`NOBATCH`) bypasses this for debugging.
- **Manual inputs** (manual affine registrations, masks, QC exclusion CSVs in `manual/common/qc_manifest/`) live under `$ROOT/manual`; automated outputs go under `$ROOT/work/<id>/...`, with flat QC images in `work/<id>/qc/`. Many steps produce ITK-SNAP workspaces (`.itksnap`) for visual QC.

## Other pieces

- `yaml/*.template.yaml` — Kubernetes Job templates for GCP processing; `svs_to_cloud.sh` replaces `%PLACEHOLDER%` tokens (e.g. `%JOBID%`, `%INPUT%`) before `kubectl apply`.
- `histo-preproc/` — Docker image and scripts for slide preprocessing (openslide, x16 pyramid generation) run in the cloud; `histo-burden/` — WildCat burden inference.
- `lightbox.sh <lb_*.json> <output> ...` — builds the QC montage images (e.g. `work/<id>/qc/*.png`) from a JSON layout spec; `itksnap/dispmap_*.txt`, `labels16.txt`, `hot_colormap.txt` — display/label assets used when building workspaces and QC images.
- Root-level `.py`/`.R` files are helpers called from the shell pipelines (e.g. `blockface_z_match.R`, `process_raw_slide.py`, `read_manifest_gdrive.py` / `download_gdrive_csv.py` for manifests kept in Google Sheets).
- Manifest CSVs edited in Excel can end up with Windows line endings and break the scripts; fix them with `dos2unix` (see `docs/source/tips_and_tricks.md`).
