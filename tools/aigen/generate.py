#!/usr/bin/env python3
"""Generate the project's 2D art from committed recipes.

    tools/aigen/.venv/bin/python tools/aigen/generate.py            # everything
    ... generate.py --recipe tools/aigen/prompts/textures.yaml      # one recipe
    ... generate.py --only gear --only iron_ore                     # some items
    ... generate.py --check                                         # no GPU needed
    ... generate.py --verify                                        # regenerate + compare

`--check` re-reads the committed art and manifest and re-asserts every claim
made about it (tiling, icon canvas size, image hash). It needs no GPU and no
model weights, so it is the gate worth running in CI.

`--verify` is the real reproducibility test: it regenerates from the committed
settings into a scratch directory and reports the pixel difference against the
committed PNG.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))

from aigen import framing, manifest as manifest_mod, pipeline, recipes  # noqa: E402
from aigen.tiling import DEFAULT_TOLERANCE  # noqa: E402

DEFAULT_PROMPTS = HERE / "prompts"
#: Committed art. NOT tools/aigen/output/, which is gitignored scratch space.
DEFAULT_OUT = REPO / "assets" / "generated"
#: Equivalence threshold for --verify, in mean absolute 0-255 levels. fp16
#: sampling is not bit-stable across library and driver versions; anything
#: under this is visually indistinguishable.
VERIFY_TOLERANCE = 2.0


def find_recipes(paths: list[Path]) -> list[Path]:
    found: list[Path] = []
    for path in paths:
        if path.is_dir():
            found.extend(sorted(path.glob("*.yaml")))
        else:
            found.append(path)
    if not found:
        raise SystemExit(f"no recipe files found in {[str(p) for p in paths]}")
    return found


def jobs_for(recipe_paths: list[Path], only: list[str]) -> list[recipes.Job]:
    jobs: list[recipes.Job] = []
    for path in recipe_paths:
        jobs.extend(recipes.load_jobs(path))
    if only:
        wanted = set(only)
        jobs = [job for job in jobs if job.id in wanted]
        missing = wanted - {job.id for job in jobs}
        if missing:
            raise SystemExit(f"no such item(s) in the recipes: {sorted(missing)}")
    return jobs


def manifest_path(out_dir: Path, kind: str) -> Path:
    return out_dir / f"{kind}s" / "manifest.json"


def cmd_generate(args) -> int:
    jobs = jobs_for(find_recipes(args.recipe), args.only)
    out_dir = Path(args.out)
    pipeline.configure_cache(args.models)

    backend = None
    failures = 0
    icons_by_kind: dict[str, list] = {}

    for index, job in enumerate(jobs, 1):
        if backend is None or not backend.fits(job):
            print(f"==> loading {job.model.id}", flush=True)
            backend = pipeline.Backend.load(job, args.models)
            backend.preflight(jobs)

        kind_dir = out_dir / f"{job.kind}s"
        sheet = manifest_mod.Manifest.load(manifest_path(out_dir, job.kind))

        print(f"[{index}/{len(jobs)}] {job.kind} {job.id} "
              f"({job.width}x{job.height}, {job.steps} steps, seed {job.seed})",
              flush=True)
        record, image = pipeline.generate(job, backend, kind_dir)
        sheet.add(record)
        sheet.save(manifest_path(out_dir, job.kind))
        icons_by_kind.setdefault(job.kind, []).append(image)

        detail = f"{record.seconds:.1f}s, peak VRAM " \
                 f"{record.peak_vram_bytes / 1e9:.2f} GB"
        if record.tiling:
            verdict = "seamless" if record.tiling["seamless"] else "SEAM"
            detail += (f", {verdict} x={record.tiling['x_ratio']:.2f} "
                       f"y={record.tiling['y_ratio']:.2f}")
            if not record.tiling["seamless"]:
                failures += 1
        print(f"      -> {record.path}  {detail}", flush=True)

    for kind, images in icons_by_kind.items():
        if kind == "icon" and len(images) > 1:
            sheet_path = out_dir / "icons" / "_contact_sheet.png"
            framing.contact_sheet(images).save(sheet_path)
            print(f"==> contact sheet at 64px: {sheet_path}", flush=True)

    if failures:
        print(f"\n{failures} texture(s) failed the tiling check.", file=sys.stderr)
    return 1 if failures else 0


def cmd_sweep(args) -> int:
    """Render several seeds for an item into scratch space, to choose from.

    Prompt wording gets a texture into the right neighbourhood; the seed
    decides whether this particular roll is any good. Sweeping in gitignored
    scratch and then committing the winning seed back into the recipe is the
    intended workflow -- it keeps "we picked this one" an explicit, recorded
    decision rather than an accident nobody can reproduce.
    """
    import dataclasses

    jobs = jobs_for(find_recipes(args.recipe), args.only)
    out_dir = Path(args.out)
    pipeline.configure_cache(args.models)

    backend = None
    for job in jobs:
        if backend is None or not backend.fits(job):
            backend = pipeline.Backend.load(job, args.models)
            backend.preflight(jobs)
        for offset in range(args.sweep):
            seed = job.seed + offset
            candidate = dataclasses.replace(job, seed=seed)
            record, _ = pipeline.generate(
                candidate, backend, out_dir / f"{job.id}"
            )
            detail = ""
            if record.tiling:
                detail = (f"  tiling x={record.tiling['x_ratio']:.2f} "
                          f"y={record.tiling['y_ratio']:.2f}")
            print(f"  {job.id} seed {seed} -> "
                  f"{out_dir / job.id / (candidate.id + '.png')}{detail}", flush=True)
            (out_dir / job.id / f"{job.id}.png").rename(
                out_dir / job.id / f"seed_{seed}.png"
            )
    print(f"\nSweep written to {out_dir} (gitignored). Put the winning seed "
          "back into the recipe and regenerate.")
    return 0


def cmd_check(args) -> int:
    """Re-assert every claim made about the committed art. No GPU, no weights."""
    from PIL import Image

    from aigen import tiling

    out_dir = Path(args.out)
    recipe_jobs = {job.id: job for job in jobs_for(find_recipes(args.recipe), [])}
    problems: list[str] = []
    checked = 0

    for kind in ("texture", "icon"):
        path = manifest_path(out_dir, kind)
        if not path.exists():
            continue
        for record in manifest_mod.Manifest.load(path).records:
            checked += 1
            image_path = out_dir / record.path
            label = f"{kind} {record.id}"
            if not image_path.exists():
                problems.append(f"{label}: manifest lists {record.path}, missing")
                continue
            if pipeline.sha256_file(image_path) != record.image_sha256:
                problems.append(f"{label}: image hash does not match the manifest")
            image = Image.open(image_path)
            if list(image.size) != list(record.image_size):
                problems.append(
                    f"{label}: {image.size} on disk, manifest says {record.image_size}"
                )
            job = recipe_jobs.get(record.id)
            if job is None:
                problems.append(f"{label}: committed but absent from every recipe")
            elif not record.matches(job):
                problems.append(
                    f"{label}: recipe has changed since this image was generated "
                    "-- regenerate it or revert the recipe"
                )
            if kind == "texture":
                report = tiling.check_tiling(image)
                if not report.seamless:
                    problems.append(f"{label}: not seamless -- {report.summary()}")
            if kind == "icon":
                expected = (record.settings["canvas_px"],) * 2
                if image.size != expected:
                    problems.append(f"{label}: icon is {image.size}, want {expected}")

    sizes = {
        tuple(r.image_size)
        for kind in ("icon",)
        if manifest_path(out_dir, kind).exists()
        for r in manifest_mod.Manifest.load(manifest_path(out_dir, kind)).records
    }
    if len(sizes) > 1:
        problems.append(f"icons are not all one size: {sorted(sizes)}")

    print(f"checked {checked} committed image(s) "
          f"(tiling tolerance {DEFAULT_TOLERANCE})")
    for problem in problems:
        print(f"  FAIL {problem}", file=sys.stderr)
    if not problems:
        print("all committed art matches its recipe and passes its own claims")
    return 1 if problems else 0


def cmd_verify(args) -> int:
    """Regenerate committed art from its committed settings and compare."""
    out_dir = Path(args.out)
    jobs = {job.id: job for job in jobs_for(find_recipes(args.recipe), args.only)}
    pipeline.configure_cache(args.models)

    targets = []
    for kind in ("texture", "icon"):
        path = manifest_path(out_dir, kind)
        if path.exists():
            for record in manifest_mod.Manifest.load(path).records:
                if record.id in jobs:
                    targets.append((record, jobs[record.id]))
    if not targets:
        raise SystemExit("nothing to verify")

    backend = None
    worst = 0.0
    problems = 0
    with tempfile.TemporaryDirectory() as scratch:
        for record, job in targets:
            if not record.matches(job):
                print(f"  SKIP {record.id}: recipe changed since generation")
                problems += 1
                continue
            if backend is None or not backend.fits(job):
                backend = pipeline.Backend.load(job, args.models)
            _, image = pipeline.generate(job, backend, Path(scratch) / f"{job.kind}s")
            diff = pipeline.pixel_difference(out_dir / record.path, image)
            worst = max(worst, diff)
            ok = diff <= VERIFY_TOLERANCE
            print(f"  {'ok  ' if ok else 'FAIL'} {record.id}: "
                  f"mean abs diff {diff:.3f} levels")
            problems += 0 if ok else 1

    print(f"\nworst difference {worst:.3f} levels "
          f"(tolerance {VERIFY_TOLERANCE})")
    return 1 if problems else 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--recipe", type=Path, action="append", default=None,
                        help="recipe file or directory (default: tools/aigen/prompts)")
    parser.add_argument("--only", action="append", default=[],
                        help="restrict to these item ids (repeatable)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output directory (default: {DEFAULT_OUT})")
    parser.add_argument("--models", type=Path, default=pipeline.DEFAULT_MODELS_DIR,
                        help="gitignored weights cache")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true",
                      help="verify committed art against its manifest (no GPU)")
    mode.add_argument("--verify", action="store_true",
                      help="regenerate and compare pixels against committed art")
    mode.add_argument("--sweep", type=int, metavar="N",
                      help="render N consecutive seeds per item into scratch, "
                           "to pick one from (use with --out and --only)")
    args = parser.parse_args(argv)
    if args.recipe is None:
        args.recipe = [DEFAULT_PROMPTS]

    if args.sweep:
        return cmd_sweep(args)
    if args.check:
        return cmd_check(args)
    if args.verify:
        return cmd_verify(args)
    return cmd_generate(args)


if __name__ == "__main__":
    raise SystemExit(main())
