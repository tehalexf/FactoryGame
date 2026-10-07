# aigen — local AI texture and icon generation

Generates the project's 2D art on the local GPU from committed recipes. No
per-image cost, no external service, and — the part that matters — no image
that nobody can reproduce.

The committed sample set lives in [`assets/generated/`](../../assets/generated).

## Quick start

```bash
tools/aigen/setup.sh                                    # once
tools/aigen/.venv/bin/python tools/aigen/generate.py    # generate everything
```

Other modes:

```bash
# one recipe, or a few items
... generate.py --recipe tools/aigen/prompts/textures.yaml
... generate.py --only gear --only iron_ore

# re-assert every claim about the committed art. No GPU, no weights, ~1s.
... generate.py --check

# the real reproducibility test: regenerate and compare pixels
... generate.py --verify

# explore seeds in gitignored scratch before committing a choice
... generate.py --only soot_brick --sweep 6 --out tools/aigen/output/sweep

# the test suite (also runs the --check assertions, as pytest)
cd tools/aigen && .venv/bin/python -m pytest
```

## Do not disturb the system torch

The machine has a working `torch 2.12.1+cu130` with CUDA in **system**
dist-packages. It is not ours to upgrade, and pip is PEP 668-locked.

`setup.sh` therefore creates `.venv` with `--system-site-packages` so torch is
*inherited*, and `requirements.txt` deliberately contains no `torch`,
`torchvision` or `nvidia-*` entry. It also verifies CUDA before and after
installing, and refuses to continue rather than "fixing" a missing CUDA by
reinstalling anything.

If `torch.cuda.is_available()` ever returns False, something else is wrong.
Do not reinstall torch.

## Reproducibility

A recipe in `prompts/` holds the model, revision, shared style, per-item
prompt and every sampler setting. The recipe is committed; so is a manifest
next to the art recording the full resolved settings, the model licence, the
image hash, the measured tiling and the torch/diffusers versions used.

Four things make "regenerate it" real rather than aspirational:

- **Seeds are mandatory.** A recipe item without one is a hard error.
- **Unknown settings are a hard error.** A typo'd `stpes: 40` that silently
  did nothing would produce an image the recipe does not describe.
- **Prompt overflow is a hard error.** CLIP's context is 77 tokens and
  diffusers truncates past it with only a warning; a shared style quietly cut
  in half is the worst failure this tool could have, so `generate.py` refuses
  to run instead.
- **The sampler is deterministic.** DPM-Solver++ (2M, Karras) with a CPU-side
  seeded generator. Ancestral samplers inject fresh noise per step and drift.

Measured on this machine: `--verify` regenerates all 18 committed images
**bit-identically** (mean absolute difference 0.000 levels). The threshold is
2.0 levels rather than zero because fp16 sampling is not promised to be
bit-stable across driver and library upgrades.

## Tiling is measured, not assumed

Seamless textures are produced by patching every `Conv2d` in the UNet and VAE
to `padding_mode="circular"`, so a convolution reading off the right edge gets
pixels from the left edge instead of zeros.

That is the easy half. The hard half is knowing it worked, so every texture is
measured: the pixel step across the wrap boundary is compared against the 95th
percentile of interior steps. ~1.0 means the boundary is indistinguishable
from anywhere else in the image; a seam scores far higher. See
`aigen/tiling.py` for why the comparator is a percentile and not the mean.

The separation is wide and was checked against a negative control — the same
8 prompts and seeds rendered with circular padding **off**:

| | with padding | without padding |
|---|---|---|
| range | 0.43 – 1.05 | 1.12 – 4.77 |
| verdict at tolerance 1.5 | 8/8 seamless | 7/8 correctly rejected |

The one texture that passes without padding is `cast_iron_plate`, a dense
high-frequency pitted surface where a seam genuinely does hide in the noise.
That is a true result, not a miss: a seam you cannot find is not a seam that
will show up on a Factory floor.

`tests/test_committed_art.py` goes further and re-measures the committed PNGs
after **rolling** them — a genuinely seamless texture tiles from any offset,
so rolling moves the wrap boundary into what used to be the middle of the
image and re-tests there. It also splices two different textures together and
asserts the metric still rejects that, so a loosened tolerance cannot quietly
make the whole check vacuous.

## Icons are framed by arithmetic

An icon set is judged as a set. The model is never trusted to frame anything:

1. Render the subject at 1024 on a flat backdrop.
2. Key the backdrop out (`aigen/framing.py`).
3. Scale the subject's bounding box so its long side is exactly
   `canvas_px * (1 - 2 * margin)` and centre it.

So every icon is exactly 256x256 with its subject filling 84% of the canvas,
whatever the model drew and wherever it drew it.

Keying is the fiddly part, because SDXL never paints a genuinely flat
backdrop. It paints a studio sweep with a soft cast shadow. The implementation
fits a smooth quadratic surface to the border ring and measures against that,
flood-fills only from the border so enclosed detail survives, and walks into
shadow by small bounded steps.

**The deliberate trade-off:** shadow removal is capped
(`SHADOW_TOLERANCE = 40`) so the fill cannot reach into a dark steel subject
and hollow it out. A faint surviving shadow nudges a bounding box; a hollowed
subject is an unusable icon. Both directions are pinned by tests.

`assets/generated/icons/_contact_sheet.png` renders the set at 64px, because
whether icons are distinguishable in an inventory grid is only answerable by
looking at them all together, small.

## Models

| Model | Used for | Licence | Why |
|---|---|---|---|
| `stabilityai/stable-diffusion-xl-base-1.0` @ `4621659` | textures and icons | CreativeML Open RAIL++-M | Ungated, ~7 GB, and its all-convolutional UNet is what makes circular-padding tiling work |

Weights are downloaded to `tools/aigen/models/` and **gitignored**. Only
prompts, settings, manifests and output art are committed.

### Why not FLUX.1-schnell

It was the preferred option and it is not usable here:

- The official `black-forest-labs/FLUX.1-schnell` repo is **gated** and needs
  an HF token, which this environment does not have. (The weights are
  Apache-2.0; the *repo* is what is gated. Ungated mirrors exist.)
- More fundamentally, it does not fit. The bf16 weights are ~34 GB across the
  12B transformer and T5-XXL, against ~22 GB of free VRAM and **25 GB of
  total system RAM** on this machine. Running it would mean quantising, which
  trades away the bit-exact reproducibility demonstrated above.
- For the tiling half it would be the wrong tool anyway. Circular padding
  works because SDXL's UNet is convolutional. Flux is a transformer; patching
  convolutions only reaches its VAE, so the seams come back.

The pipeline is model-agnostic — `model:` is a recipe field — so dropping Flux
in later is a recipe edit plus a token, not a rewrite.

## Art direction

Per [`GLOSSARY.md`](../../GLOSSARY.md), Dieselpunk here is 1920s-40s heavy
industry: cast iron, welded steel, olive drab, hydraulics, grime. Explicitly
**not** Victorian steampunk — no brass, copper, polished wood or whimsy.

Those three metals are named in every negative prompt, because SDXL reaches
for brass and copper unprompted the moment "industrial" appears. For the same
reason the material palette has no oxidised copper in it, despite copper being
an obvious choice for an industrial texture set.

## Layout

```
tools/aigen/
  setup.sh            venv on top of the system torch
  generate.py         CLI: generate / --sweep / --check / --verify
  requirements.txt    pinned; contains no torch, on purpose
  prompts/*.yaml      committed recipes — the thing you edit
  aigen/
    recipes.py        recipe loading, validation, job fingerprints
    tiling.py         circular padding, and the seam measurement
    framing.py        backdrop keying and fixed icon framing
    manifest.py       committed provenance records
    pipeline.py       the GPU plumbing (thin, on purpose)
  tests/              45 tests, no GPU needed
  models/             gitignored weights cache
  output/             gitignored scratch for sweeps
```

Everything that can be reasoned about without a GPU lives outside
`pipeline.py`, which is why the test suite runs in about a second.

## Performance

RTX 5090, SDXL base at 1024x1024, fp16:

| | steps | time | peak VRAM |
|---|---|---|---|
| texture (seamless) | 40 | ~6.5 s | 12.4 GB |
| icon | 30 | ~4.8 s | 11.3 GB |

The full 18-image set regenerates in about two minutes including model load.
