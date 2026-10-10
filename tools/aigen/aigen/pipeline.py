"""The GPU half: turn a Job into a PNG on disk plus a provenance Record.

Deliberately thin. Everything that can be reasoned about or tested without a
GPU lives in `recipes`, `tiling`, `framing` and `manifest`; this module is the
plumbing that wires a diffusion model to those pieces. It is not unit-tested,
because mocking a sampler would only prove the mock works. What *is* verified
is the output: every texture's tiling is measured, every icon's geometry is
fixed by `framing`, and `--verify` regenerates from the committed manifest and
compares pixels.

Reproducibility notes, which are the reason several things look fussy:

* The RNG is a **CPU** generator. CUDA's RNG stream differs between
  architectures; seeding on the CPU and letting the latents transfer keeps a
  seed meaningful across machines.
* The default scheduler is DPM-Solver++ (2M) with Karras sigmas, which is
  fully deterministic. Ancestral samplers inject fresh noise each step and are
  far more sensitive to library version drift.
* `torch` is loaded, never installed. See setup.sh.
"""

from __future__ import annotations

import hashlib
import os
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from . import framing, tiling
from .manifest import Record
from .recipes import Job

#: Model weights and the HF cache live here -- gitignored, never committed.
DEFAULT_MODELS_DIR = Path(__file__).resolve().parent.parent / "models"


def _schedulers():
    from diffusers import (
        DDIMScheduler,
        DPMSolverMultistepScheduler,
        EulerAncestralDiscreteScheduler,
        EulerDiscreteScheduler,
        UniPCMultistepScheduler,
    )

    return {
        # Deterministic; the default precisely because it is.
        "dpmpp_2m_karras": lambda c: DPMSolverMultistepScheduler.from_config(
            c, use_karras_sigmas=True, algorithm_type="dpmsolver++"
        ),
        "dpmpp_2m": lambda c: DPMSolverMultistepScheduler.from_config(
            c, algorithm_type="dpmsolver++"
        ),
        "unipc": lambda c: UniPCMultistepScheduler.from_config(c),
        "euler": lambda c: EulerDiscreteScheduler.from_config(c),
        # Ancestral: re-noises every step, so least reproducible. Available,
        # not default.
        "euler_a": lambda c: EulerAncestralDiscreteScheduler.from_config(c),
        "ddim": lambda c: DDIMScheduler.from_config(c),
    }


def configure_cache(models_dir: Path | str = DEFAULT_MODELS_DIR) -> Path:
    """Point Hugging Face at the gitignored models directory.

    Set before any `diffusers` import that resolves a cache path, so weights
    never land in `~/.cache` where they would be invisible to the repo's
    ignore rules.
    """
    models_dir = Path(models_dir)
    models_dir.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("HF_HOME", str(models_dir))
    return models_dir


@dataclass
class Backend:
    """A loaded diffusion model, reused across every Job that names it."""

    model_id: str
    revision: str | None
    pipe: object
    torch_dtype: str
    device: str

    @classmethod
    def load(cls, job: Job, models_dir: Path | str = DEFAULT_MODELS_DIR) -> "Backend":
        configure_cache(models_dir)
        import diffusers.utils.logging as diffusers_logging
        import torch
        import transformers
        from diffusers import AutoPipelineForText2Image

        # Progress bars and deprecation chatter drown the one line per image
        # that actually matters. Prompt truncation is handled by `preflight`,
        # not by hoping someone reads a warning.
        transformers.logging.set_verbosity_error()
        diffusers_logging.set_verbosity_error()
        diffusers_logging.disable_progress_bar()

        if not torch.cuda.is_available():
            raise RuntimeError(
                "no CUDA device visible. This pipeline is GPU-only by design; "
                "do NOT reinstall torch to work around this."
            )

        pipe = AutoPipelineForText2Image.from_pretrained(
            job.model.id,
            revision=job.model.revision,
            dtype=torch.float16,
            variant=job.model.variant or "fp16",
            use_safetensors=True,
        )
        pipe.to("cuda")
        pipe.set_progress_bar_config(disable=True)
        # Attention slicing off: 32 GB of VRAM means the fast path fits, and
        # slicing changes numerics, which would undermine reproducibility.
        if hasattr(pipe, "watermark"):
            pipe.watermark = None
        return cls(
            model_id=job.model.id,
            revision=job.model.revision,
            pipe=pipe,
            torch_dtype="float16",
            device="cuda",
        )

    def fits(self, job: Job) -> bool:
        return job.model.id == self.model_id and job.model.revision == self.revision

    def token_overflow(self, text: str) -> int:
        """How many tokens of `text` the text encoder would throw away.

        CLIP's context is 77 tokens and diffusers truncates past that with
        only a warning. A recipe whose shared style gets silently cut is the
        worst case this tool can produce: the committed prompt no longer
        describes the committed image, and consistency across the set quietly
        stops holding. So overflow is treated as a recipe error, not a warning.
        """
        tokenizer = getattr(self.pipe, "tokenizer", None)
        if tokenizer is None:
            return 0
        limit = tokenizer.model_max_length
        length = len(tokenizer(text).input_ids)
        return max(0, length - limit)

    def preflight(self, jobs: list[Job]) -> None:
        """Reject prompt overflow before spending GPU time on the whole set."""
        problems = []
        for job in jobs:
            if not self.fits(job):
                continue
            for label, text in (("prompt", job.full_prompt), ("negative", job.negative)):
                over = self.token_overflow(text)
                if over:
                    problems.append(
                        f"  {job.id}: {label} is {over} token(s) over the "
                        f"{self.pipe.tokenizer.model_max_length}-token limit"
                    )
        if problems:
            raise ValueError(
                "prompts would be truncated by the text encoder, so the "
                "committed recipe would not describe the committed image:\n"
                + "\n".join(problems)
                + "\nShorten the item prompt or the shared style."
            )

    def _apply_scheduler(self, name: str) -> None:
        builders = _schedulers()
        if name not in builders:
            raise ValueError(
                f"unknown scheduler {name!r}; known: {sorted(builders)}"
            )
        base = getattr(self, "_base_scheduler_config", None)
        if base is None:
            base = dict(self.pipe.scheduler.config)
            self._base_scheduler_config = base
        self.pipe.scheduler = builders[name](base)

    def render(self, job: Job) -> Image.Image:
        """Sample one image. Seamless jobs run with circular convolutions."""
        import torch

        self._apply_scheduler(job.scheduler)
        generator = torch.Generator(device="cpu").manual_seed(job.seed)

        wrapped = []
        if job.seamless:
            wrapped = [
                getattr(self.pipe, "unet", None),
                getattr(self.pipe, "vae", None),
            ]

        with tiling.circular_padding(*wrapped):
            result = self.pipe(
                prompt=job.full_prompt,
                negative_prompt=job.negative or None,
                width=job.width,
                height=job.height,
                num_inference_steps=job.steps,
                guidance_scale=job.guidance,
                generator=generator,
                output_type="pil",
            )
        return result.images[0]

    def environment(self) -> dict:
        """Versions that are part of the reproducibility contract."""
        import diffusers
        import torch

        return {
            "torch": torch.__version__,
            "diffusers": diffusers.__version__,
            "dtype": self.torch_dtype,
            "gpu": torch.cuda.get_device_name(0),
        }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def finish_icon(raw: Image.Image, job: Job) -> tuple[Image.Image, bool]:
    """Key the backdrop out and frame to the fixed icon canvas.

    Returns the icon and whether keying actually found a subject. If the model
    produced a busy, edge-to-edge image the flood fill finds no backdrop; the
    icon is then framed from the whole image rather than silently emitting a
    blank PNG, and the manifest records that it was not keyed.
    """
    cut = framing.alpha_from_flat_background(raw, tolerance=job.key_tolerance)
    alpha = np.asarray(cut)[:, :, 3]
    keyed = bool((alpha == 0).mean() > 0.02)
    if not keyed:
        cut = raw.convert("RGBA")
    icon = framing.frame_to_canvas(
        cut, canvas_px=job.canvas_px, margin_frac=job.margin_frac
    )
    return icon, keyed


def tiling_json(image: Image.Image) -> dict:
    """The measured tiling verdict, in the shape the manifest stores."""
    report = tiling.check_tiling(image)
    return {
        "x_ratio": round(report.x_ratio, 4),
        "y_ratio": round(report.y_ratio, 4),
        "tolerance": report.tolerance,
        "seamless": report.seamless,
    }


def generate(job: Job, backend: Backend, out_dir: Path) -> tuple[Record, Image.Image]:
    """Render `job`, post-process by kind, write the PNG, return its Record."""
    import torch

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{job.id}.png"

    torch.cuda.reset_peak_memory_stats()
    started = time.perf_counter()
    raw = backend.render(job)
    torch.cuda.synchronize()
    seconds = time.perf_counter() - started
    peak = int(torch.cuda.max_memory_allocated())

    outcome: dict = {}
    if job.kind == "icon":
        image, keyed = finish_icon(raw, job)
        if not keyed:
            outcome["notes"] = (
                "backdrop keying found no background; framed from the full image"
            )
    else:
        image = raw
        outcome["tiling"] = tiling_json(raw)

    image.save(path, format="PNG", optimize=True)

    return (
        Record.of(
            job,
            path=f"{job.kind}s/{path.name}",
            image_sha256=sha256_file(path),
            image_size=image.size,
            seconds=seconds,
            peak_vram_bytes=peak,
            environment=backend.environment(),
            **outcome,
        ),
        image,
    )


def pixel_difference(a: Image.Image | Path, b: Image.Image | Path) -> float:
    """Mean absolute per-channel difference, 0-255. Used by `--verify`.

    Bit-identical regeneration is not promised across driver or library
    upgrades, so `--verify` asserts *equivalence* with a small threshold
    rather than hash equality.
    """
    left = Image.open(a) if isinstance(a, (str, Path)) else a
    right = Image.open(b) if isinstance(b, (str, Path)) else b
    if left.size != right.size:
        return float("inf")
    mode = "RGBA" if "A" in left.mode or "A" in right.mode else "RGB"
    lhs = np.asarray(left.convert(mode), dtype=np.float64)
    rhs = np.asarray(right.convert(mode), dtype=np.float64)
    return float(np.abs(lhs - rhs).mean())
