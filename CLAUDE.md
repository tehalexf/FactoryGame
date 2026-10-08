# DEEP FOUNDRY — working notes

How to build, run and test this project, and the conventions the code follows.
Design lives in [docs/DESIGN.md](docs/DESIGN.md), vocabulary in
[GLOSSARY.md](GLOSSARY.md), architecture rationale in [docs/adr/](docs/adr/).

## Commands

```bash
tools/assets/link_licensed.sh    # point this checkout's assets_licensed/ at the one with the packs
tools/assets/link_licensed.sh --check  # what purchased packs can this checkout actually see?
tools/assets/run_tests.sh        # asset pipeline: licence guard, FBX conversion, Godot import
tools/assets/generate_machines.sh  # regenerate every Machine mesh from its declaration
tools/assets/convert_weapons.sh  # first-person viewmodels, OUT of the repo; no-op without the packs
tools/assets/convert_props.sh    # set-dressing props, OUT of the repo; no-op without the packs
tools/assets/convert_audio.sh    # hero sound cues, OUT of the repo; no-op without the bundle
tools/visual/shot.sh out.png eye # screenshot a working Factory (eye|survey|ground). Needs Xvfb.
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png routing
                                 # the same, through the player's own camera (placing|routing|running)
tools/visual/frame_cost.sh       # what the yard costs, with a full Factory and a Wave
ENEMY_COUNT=200 tools/visual/frame_cost.sh   # the same, with a Wave big enough to be a scale claim
SHOT_SCRIPT=tools/visual/compose_wave_shot.gd tools/visual/shot.sh out.png "pair bare"
                                 # a Wave arriving (swarm|pair|boss|distance; + hud, + bare)
tools/run_tests.sh              # the Simulation and the Godot layer, headless
tools/run_tests.sh determinism   # only tests whose case.method contains "determinism"
tools/balance/measure.sh         # play every balance scenario headless and print the table
tools/balance/measure.sh --scenario competent --verbose   # one Run, with its per-minute trace
python3 tools/tuning_dashboard.py  # edit content/tuning.toml in a browser, with reset and rollback
tools/tuning/run_tests.sh        # that dashboard's own tests, Python
tools/release/build_windows.sh    # a verified Windows build, from WSL2
tools/release/build_windows.sh --push        # the same, published to itch.io
python3 tools/release/preflight.py --push    # can I build and publish? why not?
godot --path .                   # run the game
godot --headless --path . --quit-after 120   # launch headless for 120 frames
bash tools/git/install_hooks.sh   # once per clone: the licence guard, for git AND jj
```

The main checkout is a colocated jj workspace as well as a git one. git is
unchanged and still the only thing CI, `gh` and the release scripts see; the jj
command crib — and the licence rule under jj, which is **not** the git one — is
in [Version control](#version-control-git-and-jj-alongside-it) below.

The tuning dashboard is the usable surface over the ~70 numbers in
`content/tuning.toml`, every one of which is a guess until somebody plays with
it. It writes the file and nothing else — the hot-reload below is what carries
the change into a running Run — validates against the subset
`sim/toml_document.gd` accepts *and* against the game's own loader before it
writes, snapshots before every write, and marks what differs from the shipped
defaults. `python3 tools/tuning_dashboard.py --check` reports the same thing
without a browser.

**Adding or renaming a key in `content/tuning.toml` means re-baselining the dashboard's
own copy**, with `python3 tools/tuning_dashboard.py --adopt-defaults`, as the genuine
last step after the numbers have settled.
`tools/tuning/tests/test_store.py::test_the_shipped_defaults_match_the_shipped_tuning_file`
asserts the two files declare the same keys, and it is the only thing that notices —
`tools/tuning/run_tests.sh` is a separate suite from the engine's, so a key added without
the re-baseline leaves the Godot suite green and that one red. #34 did exactly that and it
sat red on `integration/milestone-1` for hours, because at the time CI ran only the asset
suite. #40 fixed the CI half; this is the half a person has to remember.

**It is also a merge trap, and the shape is worth knowing.** The defaults file is a
*generated copy of a branch's own tuning file*, so two branches that each added a key each
re-baseline it, and the merge then has two mechanically-plausible versions of a file that is
supposed to be derived. Taking either side wholesale is wrong whenever the other side also
moved a value. The resolution is never to hand-merge it: take whichever side, then **re-run
`--adopt-defaults` and let it be regenerated from the merged `content/tuning.toml`**, and
check 'same keys, same values' rather than reading the diff. A textual merge that happens to
come out right is luck and not a method.

`tools/run_tests.sh` exits 0 when green and non-zero on any failure, load error,
or an unfiltered run that executed no tests. Set `GODOT=/path/to/godot` to use a
specific binary.

The asset-pipeline suite is separate because it drives Blender and Python rather
than the engine's test runner; see
[docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md). Run
`bash tools/git/install_hooks.sh` once per clone to install its licence guard as
a pre-commit hook — the repository is public and purchased assets must never be
committed.

**There are three suites and CI runs all three** — `tools/run_tests.sh`,
`tools/assets/run_tests.sh` and `tools/tuning/run_tests.sh`. See
[.github/workflows/ci.yml](.github/workflows/ci.yml); the `all suites green` job
is the single check. It provisions Godot 4.7.2, Blender 5.2.2 and ffmpeg
(`.github/ci/install_toolchain.sh`, pinned and checksummed in
`.github/ci/toolchain.env`) so that no test skips for a missing tool — a skip
whose reason is not in `.github/ci/expected_skips.txt` fails the job, because a
suite that silently skips part of itself is the same thing as one that does not
run. Two of the three did not run until #40, and a tuning-defaults regression sat
on the integration branch for days as a result.

`tools/run_tests.sh` runs `--import` first on every invocation. That is not optional: `class_name`
globals resolve through `.godot/global_script_class_cache.cfg`, which only an
import pass rebuilds, so a newly added class otherwise fails with a confusing
"Identifier not declared in the current scope".

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Godot | 4.7.2 stable | On `PATH` as `godot`. ADR 0001 originally said 4.6; amended. |
| scons | 4.11.1 | For GDExtension builds. Not needed yet. |
| Blender | 5.2.2 LTS | Art pipeline. glTF 2.0 ships; FBX is intake only. |
| ffmpeg | **7 or newer** | Audio cue cutting. A hard floor, not a preference — see below. |
| jj (Jujutsu) | 0.46.0 | Optional. Colocated onto git — the section below, and read its licence rule before you commit anything through it. |

**The ffmpeg floor is a real requirement and it bites silently.** On 6.x —  which is
what ubuntu-24.04 ships — `wav_to_cue.py --mode loop` **exits 0 and writes a
0.048-second file where twenty-four seconds were asked for**: something in the
`asplit`/`atrim`/`asetpts`/`amix` seam behaves differently, so an ambience bed comes
out almost empty rather than wrong and obvious. #40 found it by turning CI on and
pinned 8.1.3 in `.github/ci/toolchain.env`; `wav_to_cue.FFMPEG_MINIMUM_MAJOR` then
makes it a property of the **tool** rather than of CI, because a requirement that
lives only in a workflow file is one a developer runs straight past. The cutter now
refuses a 6.x by name on every invocation, and a build with no release number — a
nightly — is allowed through as "cannot tell" rather than guessed at.

GDScript, not C#. C++ via GDExtension only when profiling demands it.

## Version control: git, and jj alongside it

git is the repository. CI is git, `gh` is git, `tools/release/` reads git, and the
agent worktrees in `.claude/worktrees/` are git's. None of that changed.

What is new is that the **main checkout** at `/home/alex/code/factorygame` is also
a **jj (Jujutsu) workspace**, *colocated*: `.git/` and `.jj/` sit side by side over
one working copy, and every jj commit is a real git commit the instant it is made.
You can use either tool, in either order, in the same checkout. jj is optional. If
you only know git, keep using git and nothing here affects you — except the licence
rule below, which you must read before you type `jj commit`.

### ⚠️ The licence rule under jj — read this before anything else

This repository is public and the main checkout holds **8.5 GB of purchased,
non-redistributable assets** under `assets_licensed/`. The rule has not changed:
**nothing from there, and nothing derived from it, may ever be committed.** What
changed is the machinery, and it changed in a way that bites.

**The licence guard is a git `pre-commit` hook, and jj does not run git hooks.**
jj has no hook system at all, and it refuses to let an alias shadow a built-in
command (`Cannot define an alias that overrides the built-in command 'commit'`).
So the hook that stops `git commit` stops nothing when you commit through jj.

What stands in for it is a **wrapper installed as the `jj` on your PATH** by
`bash tools/git/install_hooks.sh`, generated from `tools/git/jj-wrapper.sh`. Before
`commit`, `describe`, `new`, `squash`, `split`, `absorb` and `git push` it runs
`tools/assets/check_licensed_staged.py --jj` and refuses the command if the guard
fails. **Run the installer once per clone, and again whenever you install or move
jj** — `jj --version` printing 0.46.0 does not tell you the wrapper is there;
`head -3 "$(command -v jj)"` does.

**And here is the thing jj makes possible that git did not.** git has an index: a
file enters a commit only because somebody typed `git add`, and `git add` refuses
a gitignored path without `-f` and refuses *outright* to stage anything reached
through a symlink (`fatal: pathspec '...' is beyond a symbolic link`). jj has no
index. It **snapshots the working copy automatically**, on almost every command,
and the snapshot *is* the working-copy commit. It honours `.gitignore`, which is
the only thing keeping the quarantine out — so:

> The moment `assets_licensed/` stops being covered by `.gitignore`, the very next
> jj command puts the quarantine into a commit. Nobody types `add`. Nobody is
> asked. And putting the `.gitignore` line back **does not undo it** — jj keeps
> tracking a file it has already snapshotted.

Never edit the `/assets_licensed/` line in `.gitignore`. If it happens anyway:

```bash
# restore the .gitignore line first — jj will not untrack a file it would
# immediately re-snapshot
jj file untrack assets_licensed/<path>   # one path
jj abandon <rev>                         # a whole commit that carries it
jj op log && jj op restore <operation>   # or rewind the repo to before all of it
```

Two protections do survive, and neither is a substitute for the wrapper:

- **Symlinks.** jj records a symlink *as a symlink* — the target path, a few
  bytes — and never follows it. So the `assets_licensed/<pack>` symlinks an agent
  worktree uses carry no asset data into a jj snapshot either. Different mechanism
  from git's refusal, same outcome.
- **The large-file brake.** `snapshot.max-new-file-size` is set to `4MiB` for this
  repo; jj refuses to snapshot a *new* file above it and tells you so. That stops
  bulk, not a 300 KB purchased texture, so it is a brake and not a guard.

And `check_licensed_staged.py --all` runs in CI on every push, which catches it
late — after the asset is in a commit object — rather than never.

### The commands, against the git ones you would otherwise reach for

| You want | git | jj |
|---|---|---|
| see what changed | `git status` | `jj st` (or bare `jj`) |
| the log | `git log --oneline` | `jj log` |
| diff the current work | `git diff` | `jj diff` |
| stage a change | `git add -p` | nothing to do — jj snapshots the working copy |
| commit it | `git commit -am "msg"` | `jj commit -m "msg"` |
| reword what you are on | `git commit --amend` | `jj describe -m "msg"` |
| amend more work in | `git commit --amend` | just edit the files; `@` already has them |
| start the next change | — | `jj new` |
| switch branch | `git switch feat/x` | `jj new feat/x` then `jj bookmark set feat/x -r @` |
| make a branch | `git switch -c feat/x` | `jj bookmark create feat/x -r @` |
| move a branch | `git branch -f x <sha>` | `jj bookmark set x -r <rev>` |
| fetch | `git fetch` | `jj git fetch` |
| push the branch | `git push -u origin feat/x` | `jj git push --allow-new -b feat/x` |
| rebase onto the branch | `git rebase integration/milestone-1` | `jj rebase -d integration/milestone-1` |
| undo the last thing | reflog, carefully | `jj undo`, or `jj op log && jj op restore <op>` |
| throw work away | `git reset --hard` | `jj abandon <rev>` |
| who touched this line | `git blame` | `git blame` — jj has no equivalent, use git |

Three things that will trip you up if you expect git:

- **There is no staging area and no "dirty working tree".** The commit you are
  "on", `@`, already contains your uncommitted edits. `jj commit` does not collect
  changes; it closes `@` and opens a fresh empty one on top. `jj describe` just
  gives `@` a message and leaves you on it.
- **Bookmarks are git branches, but they do not follow you.** A git branch moves
  when you commit on it; a jj bookmark stays where it is until you move it. So
  after a few `jj commit`s, `jj bookmark set <name> -r @-` is what makes those
  commits pushable. **CI, `gh` and the merge flow only ever see bookmarks you have
  pushed** — they are plain refs on the remote, named exactly as before
  (`feat/<n>-<slug>`, `integration/milestone-1`).
- **`@` is a real commit, and an empty one is normal.** `jj log` showing
  `(empty) (no description set)` at the top is the expected resting state, not a
  mistake.

Useful revsets here: `trunk()` is aliased to `integration/milestone-1@origin`, so
`jj log -r '::@ ~ ::trunk()'` is "my unpushed work" and `jj rebase -d trunk()`
rebases onto the integration branch.

### ⚠️ Any jj command abandons a `git merge` in progress — including a read-only one

Measured, during #42's merge, and the failure is silent. jj **snapshots the working
copy on almost every command**, and a merge in progress is a state it has no concept
of: `MERGE_HEAD` and the staged index are a git-only arrangement, so the snapshot
rewrites git's index and what was a staged merge becomes loose worktree edits. The
content on disk is left correct, which is exactly what makes it dangerous — nothing
looks wrong.

**The command that did it was `jj --no-pager file list -r @`.** There is no such thing
as a read-only jj command in a colocated checkout: `jj st`, `jj log` and `jj file list`
all snapshot first. `jj op log` names the culprit afterwards (`snapshot working copy`,
with the offending `args:` line), which is how this was confirmed rather than guessed.

Had the merge been committed without checking, `integration/milestone-1` would have
gained a **single-parent** commit carrying the merged content with no merge recorded —
so `git branch --merged` would never have known the branch was in, and the next merge
of it would have replayed work already present.

So: **while a `git merge` is open in the main checkout, run no jj command at all**, and
assume a concurrent agent may run one. Verify before committing a merge, and the check
is two integers and a hash rather than a judgement:

```bash
git log -1 --format=%P                                   # expect two parents
git merge-tree --write-tree HEAD <branch>                # git's own merge result
git rev-parse HEAD^{tree}                                # must equal it
```

A merge whose tree equals `merge-tree`'s output is the merge git would have made,
whatever happened to the index on the way. That is what makes the recovery trustworthy
without re-running the suites: the content is proved identical to the thing that was
tested, rather than reconstructed by hand.

### jj workspaces are not git worktrees — use git in a worktree

This is the one genuine limitation, stated up front so nobody rediscovers it.

The agent worktrees under `.claude/worktrees/` are **git worktrees**. jj's own
equivalent is `jj workspace add`, and it is a different mechanism — jj will not
adopt a git worktree.

**If you are working in a worktree, use git.** Every command in the table's left
column, exactly as before, and still run `bash tools/git/install_hooks.sh` for the
git hook. Nothing else here applies to you.

And it is worth knowing *why* that is an instruction and not a preference, because
the failure is silent. A git worktree has no `.jj/` of its own, so jj does not stop
there — **it walks up, finds the main checkout's `.jj/`, and operates on the main
checkout's working copy** while you are standing in the worktree. `jj st` in an
agent worktree prints the main checkout's changes as `../../../...`, and `jj commit`
there would close somebody else's work into a commit under your ticket. That is
measured behaviour, not a guess.

The wrapper on PATH refuses outright rather than letting it happen:

```
jj: refusing to run here.
  this git worktree:   /home/alex/code/factorygame/.claude/worktrees/agent-…
  the jj workspace:    /home/alex/code/factorygame
```

jj is for the main checkout, which is where merges, releases and one-off tooling
work happen. Do not run `jj workspace add` inside `.claude/worktrees/` either:
agents are live in those directories, and jj and git would disagree about who owns
the working copy.

### Where things live

```
.jj/                     jj's store. Gitignored; must never reach the remote.
.jj/repo/config.toml     this repo's jj config (user, trunk(), the 4MiB brake)
tools/git/jj-wrapper.sh  the licence-guard wrapper, version-controlled template
tools/git/install_hooks.sh  installs the git hook AND generates ~/.local/bin/jj
~/.local/opt/jj-0.46.0/jj   the real binary. The `jj` on PATH is the wrapper.
```

`SKIP_JJ_WRAPPER=1 bash tools/git/install_hooks.sh` installs only the git hook.
`tools/assets/tests/test_jj_guard.py` is what proves the jj half still refuses a
purchased asset; CI installs jj so those tests run rather than skip.

## Layout

```
sim/      the Simulation. Pure GDScript, no Godot node types, no floats.
game/     the Godot layer. Input producers and state readers only.
content/  Machine, Recipe and tuning definitions. Data, not code.
tests/    test runner, TestCase base, the balance harness, and tests/cases/ for the cases.
assets/   committed CC0 and self-authored assets. intake/ holds the source FBX.
tools/    developer scripts. tools/assets/ is the asset pipeline; tools/balance/ measures a Run.
docs/     design, ADRs, asset licensing.
```

Machine meshes are scripted output, not modelled files: `content/` declares the
footprints and ports, `tools/assets/machine_recipes.py` declares the geometry,
and `generate_machines.sh` produces `assets/machines/*.glb`. Change a dimension
by editing the declaration and re-running, never by editing a `.glb`. The grid
facts have one authority each, and the asset suite fails if a mesh and the
Simulation disagree — see [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md)
section 6.

A Machine's **silhouette is a gameplay requirement, not polish**: the core skill
in a factory game is reading your own production line at a glance.
`tools/assets/machine_silhouette.py` measures how far apart every pair of
outlines is and the asset suite fails if any two converge, so changing a recipe
cannot quietly turn two Machines back into the same dark box. The committed
contact sheets in `docs/images/` are the same claim in a picture; rebuild them
with `tools/assets/render_machines.sh`.

`game/world_view.gd` is the only consumer of those `.glb`s, and it flattens each one
once on first use. The generator splits a body into a mesh per material so the glTF can
name a shared material without embedding its textures, which Godot imports as a dozen
`MeshInstance3D`s — the wrong shape to draw fifty of, and a shape a `MultiMesh` cannot
take at all. So a body becomes **one Mesh with a surface per material, cached by id**: a
Machine is one node, a Belt tile is one instance, and fifty Smelters share one buffer.
The port markers carry no mesh and fall out of that flattening by themselves.

Three rules the renderer holds to, each with a test:

- **A body is placed, never measured.** Every body is modelled about the centre of its
  footprint with its feet on the ground, so the renderer moves it to the footprint centre
  at the layer's height and turns it by the Machine's rotation, and that is all.
- **A Machine with no body draws a box.** Adding a row to `content/machines.csv` is never
  blocked on art, so a missing `.glb` is an ordinary state and not a warning.
- **Count decides node or instance.** Machines and the Nest are nodes, pooled. Belt
  tiles, Items and Enemies are `MultiMesh` instances, because those are the three that
  reach the thousands — `test_world_view` asserts the scene tree does not grow by a node
  for any of them.

### The Enemies wear characters now, and the animation is in a texture

#38, and the ticket's own complaint was that the thing a player spends a whole Run shooting
at was the least finished thing in frame: a procedurally built carapace of boxes, sliding
across the ground with no animation, and **the same mesh for a Crawler and a Breaker** — so
the only thing separating "the sense of threat" from "the threat" on screen was a line of
HUD. Meanwhile thirteen committed CC0 characters that #18 had retargeted onto one shared
skeleton had never been drawn by anything.

**An Enemy is still never a node, and that is what shapes the whole solution.** The
idiomatic answer is an `AnimationPlayer` per Crawler and it is exactly the architecture ADR
0001 refused. So the animation lives in a texture the vertex shader samples
(`game/enemy_skin.gdshader`), and which row an Enemy is on arrives as per-instance custom
data. There is nothing per Crawler anywhere on this side of the boundary.

- **It bakes bone poses, not vertex positions**, which is the one real engineering decision
  in it. A vertex animation texture is 4858 vertices by ninety frames — 437,000 texels a
  kind, growing with the model. Skinning matrices are 23 bones by ninety frames: about two
  thousand texels, and it does not grow by one texel if the mesh triples. The price is that
  `ARRAY_BONES` is only readable through a `Skeleton3D`, so `EnemyBodies` moves the indices
  and weights into `CUSTOM0` and `CUSTOM1` and drops the skinning declaration.
- **The bake is at load time and commits nothing**, because `world_view.gd` already
  flattens every Machine `.glb` on first use for exactly this reason: what Godot imports out
  of a glTF is the wrong *shape* for a `MultiMesh`, and the fix is a transform of a
  committed asset rather than a second committed asset. A baked mesh beside the artist's
  file would be two authorities on what a Crawler looks like.
- **One MultiMesh a kind, created on the first sync** — before a Breach has released
  anything. Eagerly rather than on the first Enemy, so `test_an_enemy_is_never_a_node`
  asserts *zero* growth rather than "no more than one a kind", and so the bake is paid at
  load rather than on the frame the first Wave arrives.
- **A body is baked one metre tall and scaled by `query_enemy_hit_height_metres`** — the
  capsule a round is actually resolved against, newly exposed as a query for this. So a
  player shoots at what they can see; a constant in the renderer would be #41's ownerless
  red rectangle in a different costume. The normalisation is folded into each **bone
  matrix**, because skinning is a weighted sum whose weights total one, so `P * (Σ w M v)`
  is `Σ w (P M) v`.
- **Nothing is timed by a clock and nothing is drawn at random.** `game/enemy_animator.gd`
  is a `RefCounted` with no state about the Run at all — one step stronger than
  `WeaponAnimator`, which has transitions with lengths to remember. A `Facts` of four
  queries goes in, a role and a frame come out, and the frame is integer arithmetic over the
  tick, the Enemy's spawn tick and its **serial**. The serial is what de-locksteps six
  Crawlers released on one tick; it is issued once and never reused (#9), where an RNG draw
  would have cost the Run a draw and a clock would have cost it determinism.
- **A kind with no cast character draws the procedural carapace**, which is the rule a
  Machine with no generated `.glb` already obeys. Adding an Enemy kind is four tuning keys
  and a row, and it is never blocked on art.
- **The Siege Hulk's vent survived, and it is still the only place geometry carries a
  rule.** It is modelled in body heights with its offset in the mesh, so it is placed with
  exactly the transform the body is placed with.

**What does not read at thirty metres, and it was measured rather than hoped.** A Siege Hulk
is unmistakable at any range and a swarm reads as a crowd of bodies rather than a row of
boxes — but a Crawler and a Breaker are **not** distinguishable from one another past about
twelve metres, where they separate clearly. The mitigation was to have been the characters'
own glowing eyes, and it renders nothing: the KayKit skulls are closed meshes whose glow
vertices sit behind the front of the skull. The plumbing is fine — the same emission on the
body renders four glowing skeletons — so the wiring stays and no workaround was taken, since
moving an artist's vertices is the renderer editing the model and `depth_test_disabled` would
draw eyes through a wall. Distance readability is the open half of this ticket.

Full pipeline, the casting table, why `UAL1.glb` is still unused and what three renders
caught are in [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md) section 11. The before and
after are `docs/images/enemies_{pair,wave,boss}_{before,after}.png`, rebuilt with
`SHOT_SCRIPT=tools/visual/compose_wave_shot.gd tools/visual/shot.sh out.png <preset>`.

**What it costs**, measured with `ENEMY_COUNT=<n> tools/visual/frame_cost.sh` against the
same scenario before and after: `WorldView.sync` goes from 3.22 ms to 4.32 ms at 18 Enemies
and from 3.80 ms to 4.56 ms at 71, so about **a millisecond of a 16.67 ms frame**, plus
1.4 M primitives and 17 MB of video memory. That is the CPU rebuild only — the skinning is
in a vertex shader and Xvfb is llvmpipe, so **the GPU half of this is unmeasured here** and
wants a machine with a real card.

The lighting is the other half of the art pipeline. The generated surfaces are physically
based and mostly metal, and a metal lit by an ambient *colour* has nothing to reflect, so
it renders as a dark smear whatever its albedo says. `_sync_scenery` therefore takes both
ambient and reflections off the sky, tonemaps filmic, and carries a shadowless cool fill
opposite the sun so the far side of a boiler still reads. The palette was tuned in Blender
renders; those numbers are the second half of that tuning, and they are not
interchangeable.

### The ground, the yard and the light

The Machines were good and everything around them was not: a flat plane with a
grid texture on it, nothing else in the world, and a horizon where the Map
stopped. Three things changed, and the only way any of them was judged was by
rendering, reading the image, changing something and rendering again —
`tools/visual/shot.sh` exists for that and found three real defects nothing else
would have.

**The ground is `game/ground.gdshader`.** #20's generated maps — poured concrete,
rust, soot — sampled in **world space** so density is a number in metres, blended
over two octaves of value noise so the yard is worn in some places and not in
others. The 2 m grid is **drawn rather than textured**, from the world position,
with `fwidth` fixing the line width in *pixels*: one crisp line at any distance
and any resolution, no mip chain turning the far half into noise, fading out past
where a player could read it. It is then multiplied by the wear, which is the one
change that stops it reading as graph paper — paint on a worn patch is faint and
paint under soot is gone, where a line of uniform strength everywhere is an
overlay rather than a marking. The grid is painted **only inside the buildable
Map**; the plane itself runs 192 m further in every direction as an unpaved,
unmarked apron, so the world no longer ends at a cliff of sky.

**The yard is `game/set_dressing.gd`**, and it is the purchased props finally
being used. It is decoration and it can never become anything else: the layout is
a pure function of `query_seed()` and the grid's size, nothing is told to the
Simulation, nothing carries a collider, and asking for it does not move the hash.
Three things it is careful about:

- **It gets out of the player's way.** The whole Map is buildable, so a prop that
  stayed where a Smelter went would be a prop standing inside a Smelter. Every
  placement inside the Map sits on a tile and loses its prop when the Simulation
  reports that tile built on, which reads usefully as clearing ground to build.
  The occupancy is walked **from the Factory** into a tile set, not asked per prop
  — `_mark_obstructions`' lesson, re-learned by measuring: the per-prop version
  cost 39 ms on the frame after a build, which is a two-frame hitch every time a
  player puts something down.
- **It is anchored on the Nest, the Nodes and the Breaches**, not spread over the
  Map. Two hundred props over a 129-tile square is one prop every eighty tiles —
  statistically a yard and visibly an empty plain, because a player spends a Run
  inside a thirty-metre circle around their own Factory.
- **The props are loaded at runtime from outside the repository and are usually
  absent**, exactly as the viewmodels are, and a clone without them walks the same
  layout drawing self-authored stand-ins out of the committed Machine materials.
  See [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md) section 8.
- **And they are graded into the palette rather than tinted toward it.** The
  packs are clean modern high-visibility industrial — safety yellow, process
  teal, white — and the first pass multiplied each pack's `baseColorFactor` by a
  colour pulled toward `dieselpunk_palette.json`. That changed nothing where it
  mattered: the whole heyheythere set is drawn through one shared
  `material_override` built over the atlas, so the factor it tinted is read by
  nobody, and the foreground pipe runs stayed the brightest and newest-looking
  things in a world of grimy cast iron. `tools/assets/prop_grade.py` remaps the
  **atlas** onto the palette's own ramps at conversion time instead, forces the
  glow map to tungsten, and deepens the pack's baked occlusion into grime; the
  shared material went metallic, because a Lambertian crate beside a metal
  Machine renders twice as bright from the same albedo whatever the texture says.
  Hazard colour is not gone, it is **placed**: two prop ids wear the palette's own
  `HazardYellow` and nothing else in the yard does.

**#42 changed both of those again, and both changes came out of a render.** The playtest
said four things about the world and two of them are here.

*"The textures don't look so tiled"* and *"the ground should be slightly bumpy/textured like
real dirt"* are one file. Each generated map was read **once, at one density, on one axis** —
blending three of them over noise hides where one ends and the next begins and does nothing
at all about the fact that each repeats on a perfect lattice, which is what the eye was
actually finding. `detiled()` reads each map **twice**, once at its stated density and once
turned 21 degrees and scaled by the golden ratio so the two lattices are incommensurate, and
warps the coordinate on a slow noise ahead of both so the lattice itself wanders. The
crossfade between the two reads is deliberately **narrow**: two decorrelated reads of one
texture average to half its variance, so a wide band de-tiles the ground by flattening it,
which is one wrong answer traded for another.

And the ground wrote `ALBEDO`, `ROUGHNESS`, `METALLIC` and `SPECULAR` — **no normal at
all**. However worn the picture was, the surface was geometrically a sheet of glass: one
normal over the whole Map, so a 23-degree sun fell on every square metre identically.
`assets/generated/` is albedo-only and there is no normal map to load, so the relief is
**derived**: a three-octave world-space value-noise height field, its gradient taken by four
extra evaluations a fragment, bending the world normal and only then going to view space —
which needs no tangent frame and no UVs, and a `NORMAL_MAP` would need both. Each octave is
turned off the one below it, because three octaves of a square-lattice noise sharing an axis
would put exactly the grid back that the rest of the file removes.

**The thing that cost three renders: what is visible is the slope, not the height.** The
first attempt was "two centimetres of bump, features about a metre" — reasoned, physical,
and a one-degree tilt that the sun cannot find. It rendered as the same sheet of glass and
read, on the screenshot, as no change at all. The number that matters is
`bump_height_metres` **over** `bump_metres`, and the shipped pair was bracketed by looking:
0.12 is visibly gravel, 0.03 is invisible, 0.075 is a yard. A diagnostic render that wrote
the slope into `ALBEDO`, and then one that forced an absurd constant normal, are what
separated "the maths is too subtle" from "the plumbing does not work" — worth remembering,
because from the first image alone those two look identical.

*"Please clean up the world so it isn't just scattered objects"* is `set_dressing.gd`, and
#39's own closing note had already said the remaining problem was **layout rather than
palette** and named the symptom: pipe runs crossing the first few metres of view. The first
pass had density and no **arrangement** — every pile fell at a random bearing and radius
from its anchor and every prop in it took its own random quarter turn. A real site is not a
distribution of props. Things line up along something, and the something is almost always a
route.

So the layout now decides where the **roads** are before it places anything: a lane from the
Nest to each Node and each Breach, cornered on the grid like a Belt route. Three things hang
off that.

- **The lanes are kept clear outright**, which is the half of "clear ground where a player
  works" that no amount of better scattering would have bought. They are also, plainly, the
  paths a player walks: the Nest is where a Run starts and the Nodes are where it goes.
- **A cluster became a bay**: a filled rectangle of tiles, aligned to the grid, standing at
  a lane's kerb, long side running with the traffic, **every prop in it sharing one yaw**,
  with a counted number of gaps and the tall stock — racking, shelving, a skip — in the row
  furthest from the road. That last pair is the whole of "clusters with a reason": you can
  see what the bay is for from the road. And the shared yaw is most of the effect — a pile
  whose every member faces a different way is the most scattered thing it is possible to
  draw, which is what the old random quarter turn was producing. A spill still takes a
  random turn, because a spill has no front.
- **A pipe run runs beside a lane and along it**, never across it. The old version took a
  random axis from a random point on a ring around an anchor, and since the anchors include
  the Nest, about half of them crossed the opening view at head height. A service runs the
  length of a road on one side of it, which is where you put one and which leaves the view
  down the road clear. Catwalks the same, and more so: a deck at 3.8 m across a road is the
  one prop in the set that can hide a Machine behind it.

**The pictures are committed and they are the argument.**
[`docs/images/playtest2_yard_before.png`](docs/images/playtest2_yard_before.png) against
[`_after`](docs/images/playtest2_yard_after.png) is the eye-level view: a bright pipe run
on a diagonal across the near field, props dotted at random behind it, becoming a clear
working ground with the yard lined up along its roads.
[`playtest2_ground_before.png`](docs/images/playtest2_ground_before.png) against
[`_after`](docs/images/playtest2_ground_after.png) is the same pair at standing height and
is mostly about the floor: a smooth sheet with a texture printed on it, becoming ground.
`tools/visual/shot.sh out.png eye|ground` rebuilds them, and every finding above came from
reading one of them — none from reading the code.

**The light** kept #25's shape — ambient and reflections off the sky, filmic
tonemap, SSAO, depth fog — and changed four things. The sun dropped from 41 to 23
degrees, which is what makes the hour *stated* rather than merely not
contradicted: a 3 m Machine lays seven metres of shadow. The single shadow
cascade became four over 110 m instead of one over 160, weighted at the camera,
which is what buys the half-metre detail that seats a prop on the ground —
together with an SSAO radius down from 0.9 m to 0.38 m, because a metre-wide
darkening around a crate is not contact and a centimetre-wide one is. Glow, at a
high threshold, so the lamps in the yard read as lit rather than as bright texels.
And a saturation and contrast pass after the tonemap, because the palette is
mostly dark neutrals under a bright ochre sky and what came out the far end was
grey with a cast over it.

**One thing that pass caught, worth remembering: a colour picked against a white
background is a colour picked against the wrong thing.** The Walls and the
Machine placeholder box were at 0.30 and 0.35 albedo, where the palette runs 0.055
to 0.14, and they rendered as the brightest objects in frame. The Walls now wear
the palette's own `WeldedSteel` with the health colour as a per-instance
*multiplier* on it, which fixes the brightness and gives the cheapest built thing
in the game a surface at the same time.

The split between `sim/` and `game/` is the project's load-bearing boundary, and
it runs one way only: `game/` depends on `sim/`, never the reverse. Nothing in
`sim/` may reference `Node`, the scene tree, or any Godot type whose state is
float-based.

## The purchased packs, and why your checkout probably cannot see them

**An empty `assets_licensed/` means "not linked". It never means "not purchased".**

Read that before concluding anything from that directory, because the mistake has
already been made and it was expensive. `assets_licensed/` is gitignored — the
repository is public and nothing in there may be redistributed (docs/ASSETS.md) — and
a **git worktree is a checkout of tracked files, so it never has it**. Every agent
this project has spawned has worked in a worktree. Every one of them has opened an
empty quarantine. One of them reasoned from that emptiness that the packs were not on
this machine, concluded that a playtest's audio complaints must therefore have been
about the committed Kenney fallbacks, and fixed the fallbacks — while the 37 hero cues
sat in the main checkout, in the player's Windows build, being the sounds the player
was actually describing.

So, first thing in a new worktree:

```bash
bash tools/assets/link_licensed.sh          # one symlink per pack, from the main checkout
bash tools/assets/link_licensed.sh --check  # or just ask, and change nothing
```

`--check` exits non-zero on an empty quarantine, so it is usable as a precondition in
a script that is about to claim something about an asset.

Three things about it worth knowing rather than rediscovering:

- **It links each pack, not the directory.** `assets_licensed/.gdignore` is *tracked*
  — it is the one file in the quarantine that must be in git, because without it
  Godot's importer walks gigabytes of third-party Unity projects and WAV libraries —
  so replacing the directory with a symlink shows up as deleting a tracked file.
  Per-pack links leave it alone and `git status` stays clean, because everything under
  `assets_licensed/` is ignored anyway.
- **Godot follows the links**, and the converters and `game/sound_bank.gd` need no
  change to see them: `res://assets_licensed/generated/audio/...` resolves through a
  symlink exactly as through a directory.
- **The licence guard is undiminished**, and this was checked rather than assumed. Git
  refuses to add a path *"beyond a symbolic link"*, so no asset bytes can be staged
  through one; staging a link itself is caught by
  `tools/assets/check_licensed_staged.py` like any other quarantined path. Do not work
  around either.

The converters themselves are honest about absence — `convert_audio.sh`,
`convert_weapons.sh` and `convert_props.sh` all print a note and exit 0 with no
bundle, and the game runs without any of it. That is the point of the design and it is
also what makes the blind spot so quiet: **nothing fails when you cannot see the
packs**. It just stops being the game the player played.

## Sound

**No diegetic control ships silent.** DESIGN.md is explicit about why — IRON
NEST's most-praised quality is its sound design and its most-cited criticism is
that its loop reduces to data entry, and the line between satisfying friction and
tedium is whether the machine answers you. A lever that clunks is a reward; a
silent lever is a chore. Audio is load-bearing here, not polish.

Two files, and the same shape the renderer has:

- `game/audio_director.gd` decides **what** makes a noise, by diffing query
  results against what they said last frame — because a sound is a *change* and a
  query reports a *condition*. It holds no authoritative state, exactly as
  `WorldView` holds none; its snapshot is the same category of thing as
  `TickPump`'s leftover frame time. `cues_for_frame`, `ambience_db` and
  `sustained_cues` need no audio device, so the whole sound design is asserted
  headless in `tests/cases/test_game_audio.gd`; `sync` is the only part that
  touches a player node.
- `game/sound_bank.gd` decides **which file**, and owns the mix. Two sources: the
  hero takes cut from the Sonniss bundle into a gitignored directory outside the
  shipping tree, and the 203 committed CC0 Kenney sounds. **Every cue names both**,
  so a clone without the bundle gets a Kenney lever rather than a silent one.

Three rules, each with a test:

- **Listening changes nothing.** The director reads queries and writes nothing, so
  the same Input Action script leaves the same state hash whether anything was
  listening or not. Sound is presentation; it never reaches the Simulation.
- **Nothing is chosen at random and nothing is timed by a clock.** Variation is
  `tick % count`; the cooldowns that stop a Machine under attack buzzing are
  counted in ticks. Two Runs down the same script sound the same, which is the
  audio half of the rule `WeaponViewmodel` keeps for animation.
- **A cue resolves or it is a load error.** Cue names are constants, the catalogue
  is data, and the asset suite fails if `convert_audio.sh` cuts a cue the game
  never plays.

**The mix was reasoned and never heard, and the first playtest said so.** #21's author
wrote the gain column against a table of what ought to be louder than what and recorded
the expectation of being wrong; #35 is five reports of exactly where. Four of them were
volume or variance and are fixed by the numbers — the beds were 3 dB *above* a footstep,
the wrench's swing had one take at the volume of a Machine being built — and two were the
wrong recording chosen rather than the wrong level: a klaxon built out of a *trailer* alarm
and a Crawler that died as an "ethereal entity". Those two are repicks in
`convert_audio.sh`, and **neither has been auditioned**, because nothing in this repository
can listen and the bundle is absent from most clones.

Two rules came out of it, both now tests:

- **A bed is the floor of the mix.** `test_the_ambience_beds_sit_under_everything_they_are_a_bed_for`
  asserts the two Factory ambiences are quieter than the quietest one-shot in the
  catalogue, rather than asserting two numbers — so a later cue that goes quieter than a
  bed fails instead of disappearing underneath it.
- **A cue a player hears dozens of times a Wave has more than one take.** The mechanism was
  always there; what was missing was anybody checking which cues used it.
  `test_the_cues_a_player_hears_over_and_over_have_more_than_one_take` names them.

### The same five reports, done again against the hero takes

The paragraph above is what the mix looked like from inside a worktree, where the packs are
invisible — see "The purchased packs" above for why, and read that before trusting any claim
about an asset. **All five reports were about the hero cues**, which the main checkout has 37
of and the player's build had all of. So the fallback work stands, as what a clone hears, and
the five were done again against the files the player was describing. Three things came out
of it that outlive the five cues:

- **A hero cue has takes now.** `convert_audio.sh --takes N` cuts the N loudest separable
  takes of a recording to `name.ogg`, `name_2.ogg` …, and `SoundBank._hero_paths` walks those
  numbered suffixes. `tick % count` never knew which world it was choosing in. The takes are
  *measured*, not written down — greedy peak picking on a non-cumulative envelope, strongest
  first so raising the count appends — and **a recording with fewer separable takes than the
  recipe asked for is an error naming both numbers**, because the one thing several takes must
  be is different. That error fired twice while the five were being cut and both times it was
  right.
- **`--lead auto` lets one recorded gesture become two cues.** A real swing-to-impact is
  air and then a thud, and the game plays those as two cues; the swing is cut as the air
  ending where the thud begins, and the hit is the same take from the onset on. Two halves
  of one event beat two libraries that have never met. **The lead is measured, not
  stated**, for the same reason the in-point is: the approach is *inside* the take and its
  length is a property of the performance — 80 to 144 ms across one library's takes — so a
  recipe naming one number is wrong on every take but one. A fixed `--lead 0.22` against a
  113 ms mean was tried first and shipped four cues that were 73-91% digital silence
  followed by the leading edge of the thud they were supposed to lead into.
- **The gain column is per source where the two sources are not the same loudness.** One gain
  per cue assumes a hero cut and a Kenney take of the same event measure alike, which is true
  of the one-shots (both are peak-normalised) and false of the ambience beds by ten dB — a bed
  is RMS-normalised under a peak ceiling, where Kenney ships a mastered loop at full scale. So
  a catalogue entry may carry a fourth number, the gain for when the hero take is playing, and
  `gain_db` is its only reader. **This is why a mix number set in one world cannot be trusted
  in the other**, and it is the generalisation of the mistake that produced this section.

**"Too loud" is a measurement.** Every figure in `sound_bank.gd`'s `#35` notes is the file's
loudest 85 ms window plus its gain — what a player hears — because every hero one-shot peaks
within a dB of every other by construction, so a peak reading can only say they are all the
same. Measured that way the wrench's swing was 0.6 dB *above* the hit it lands; the "generic"
in the same report was 31 dB of missing low end; and the "hum" was 94% of a bed's energy below
200 Hz, which no amount of turning down could have fixed, because the bed is normalised on the
RMS that rumble dominated. The *busy* bed turned out to have a real alarm tone inside it,
25-38 dB above its neighbours, running continuously under a working Factory.

**What still cannot be judged here: whether any of it sounds good.** Nothing in this
repository can listen. Everything above is spectrum, envelope and level, which is enough to
catch a cue that is the wrong object or the wrong loudness and is not enough to catch one
that is merely unpleasant.

### The Telegraph is a cue, not a siren

Three attempts, and the third one is a different category rather than a better pick
inside the same one. The first was a trailer alarm in quarter notes — a designed
cinematic sting, which this file's own standard rules out. The second was measured and
argued for at length: a motorcycle horn an octave down, low-passed to 700 Hz so the
fundamental led, cut as a one-shot so the attack survived. The player heard it and said
**"the klaxon is AWFUL, just make it very subtle"**.

Two goes at "the right alarm" is enough evidence that the category is wrong. **A siren's
job is to demand attention continuously, and nothing here needs that.** The Telegraph is
already a countdown, a gauge and the Wave's named composition on the HUD — "nothing
arrives unannounced" is satisfied before the audio says a word — so the sound's job is to
make a player *look up*, not to warn them. It can be a knock.

So it is a **geofon hit**: a struck steel plate, which is what a works alarm was before
electricity, and which is a short dull thud with a long tail of nothing. Cut five seconds
long and left mostly empty, high-passed at 90 Hz and low-passed at 600, and still in
`LOOPING_CUES` so it rearticulates about every five seconds and stops on the tick the
Telegraph does. The gaps are the point: a sound that stops is one a player can think over.

Measured, with each cue's catalogue gain applied, because "subtle" has to be a number:

| cue | gain | integrated | centroid | peak |
|---|---|---|---|---|
| Telegraph, #35's | −9 dB | −19.0 LUFS | 953 Hz | −10.1 dBFS |
| **Telegraph, now** | **−24 dB** | **−45.3 LUFS** | **148 Hz** | **−25.2 dBFS** |
| `factory_bed` | −24 dB | −44.4 LUFS | 565 Hz | −31.8 dBFS |
| `factory_busy` | −20 dB | −42.9 LUFS | 1920 Hz | −23.3 dBFS |
| `turret_fire` | −12 dB | −26.0 LUFS | 332 Hz | −12.9 dBFS |
| `breach_opens` | −7 dB | −29.2 LUFS | 1996 Hz | −8.0 dBFS |
| `wave_begin` | −3 dB | −17.8 LUFS | 335 Hz | −3.9 dBFS |

It is **genuinely quiet**, said plainly rather than hedged: 26 LU quieter than the cue the
player called awful, 15 dB down at the peak, and an octave and a half lower in centroid.
Integrated it is below *both* ambience beds; what keeps it audible is the one number where
it is not, its peak, which stands 6.6 dB over the quiet bed's — because a transient against
a continuous bed costs almost no loudness to hear.
`test_the_telegraph_cue_is_the_quietest_thing_in_the_catalogue` holds it there, and
`test_the_ambience_beds_sit_under_everything_they_are_a_bed_for` was widened from the two
beds by name to `LOOPING_CUES` so that a cue which is itself quasi-ambient can sit on the
floor with them instead of failing for it.

**There is no separate Breach klaxon** — the Telegraph's is the only sustained warning in
the game. The nearest thing is `breach_opens`, and it had the same defect from the same
instinct: a 4610 Hz centroid, which is a bright splattery crack in the ear's most
sensitive band, in a game whose palette is low industry. Rolled off above 2.4 kHz and down
three decibels, to a 1996 Hz centroid. It stays a **loud one-shot**, and that is the
difference: a Breach opening happens once and being startled by it is the right response.
What was wrong there was the band, not the level.

The recordings are long source material rather than game SFX, so
`tools/assets/convert_audio.sh` is the recipe — which recording becomes which cue
and why — over `tools/assets/wav_to_cue.py`, which measures the in-point rather
than remembering it. See [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md)
section 8.

## The Simulation façade is the only seam

`sim/simulation.gd` exposes exactly three things:

```
step(actions)    advance exactly one tick
hash()           reduce the whole state to one integer
query_*(...)     read-only projections
```

Everything behind it — grid, Belts, Machines, Power, Heat, Waves, Turrets, Silo,
Delivery — is tested *through* those three, never directly. A test that reaches
into a module's internals breaks when the module is refactored and tells you
nothing about whether the game works. The one exception is leaf utility libraries
with contracts of their own — `Fixed`, `DeterministicRng`, `StateHasher`, and the
definition loaders `CsvTable`, `TomlDocument` and `Definitions` — which are tested
directly because their rounding, bit-level behaviour and error messages cannot be
observed any other way. "line 7 of recipes.csv names a rate that is not a number"
is not something `step`, `hash` or a query can tell you.

Queries return copies, never references into state. The Godot layer holds no
authoritative state whatsoever.

## Content definitions

Machines, Recipes and tuning values are **data**, in `content/`:

```
content/machines.csv    one row per Machine
content/recipes.csv     one row per Recipe
content/waves.csv       one row per tier of Wave composition
content/deliveries.csv  one row per tier of Delivery progression
content/gear.csv        one row per weapon frame and per component that fits one
content/stratagems.csv  one row per Stratagem a Silo's Charges pay for
content/tuning.toml     balance numbers that are not per-Machine or per-Recipe
```

**Adding a Machine, a Recipe, an Enemy tier to the Waves, a Delivery tier, a weapon, a
Gear component or a Stratagem is a row. It is never a code change.** There is no
registry, no enum and no Item table — the set of Items is exactly the set the
Recipes mention, interned in sorted order. Every column is documented in the
header comment of the file it belongs to; read that before adding a row.

`content/.gdignore` is load-bearing. Without it Godot's importer claims every
`.csv` in the directory as a translation table, warns on each import, and strips
the rows from an export. These files are read with `FileAccess`, not `load()`.

`Definitions.load_from_directory` returns a set that either loaded or did not:

- Machines, Recipes and Items are **sorted by id**, and tuning keys are sorted
  too, so the index space is a function of the content and not of the order rows
  happen to be written in. Row order, comments and blank lines cannot reach the
  state hash.
- A malformed value is an **error naming the file, the row and the column**.
  There are no defaults anywhere: a typo'd rate does not become 0, a missing
  tuning key does not become 0, a Machine pointing at a Recipe that does not
  exist is not quietly Recipe-less.
- A set with any error at all carries **no definitions**. Half a definition set
  is more dangerous than none, because it looks usable.
- A tuning key nothing reads is a **warning**, because a file carrying a number
  that does nothing lies to whoever is tuning it.

`Definitions.load_from_directory` reads all seven files and `Definitions.parse` takes all
seven sources, in that order. A missing one is an error naming the path, never an empty
table — and `game/definition_watcher.gd` digests all seven, so editing any of them
hot-reloads.

The **order they are read in** is not the order they are listed in, and it is load-bearing:
Recipes first (the Items are interned from them), then Machines, then Gear, then the
**Stratagems** — a `sentry` row has to name a Turret in `machines.csv` — then the Waves, then
the Deliveries, whose three unlock columns each have to name a row in one of the tables above
— and **tuning last**, because `player.starting_weapon` has to name a weapon frame that no
Delivery tier locks, which is a question only the Gear table and the Delivery table together
can answer. Errors are still gathered in *file* order, so the report reads like a list of
things to go and fix.

`sim/csv_table.gd` and `sim/toml_document.gd` are the only parsers. Both are
hand-rolled: Godot ships no TOML parser, and vendoring one into a public repo is
out (`docs/ASSETS.md`). The TOML subset is sections, `key = value`, comments,
integers, decimals, quoted strings, `true`/`false` — and nothing else. Arrays,
inline tables and dates are valid TOML and are refused by name and line number.
If you need another data file, reuse `CsvTable` rather than writing a parser —
`content/waves.csv`, `content/deliveries.csv`, `content/gear.csv` and
`content/stratagems.csv` are four worked examples of doing exactly that, and none of them
cost `CsvTable` a line.

Rates are written in decimal because that is how a human reasons about them, and
cross into fixed point exactly once, through `Fixed.from_decimal_string`, which
floors like every other lossy operation. No float exists at any point.

## Hot-reload

Editing a content file while the game runs applies the change when you save it.

`game/definition_watcher.gd` owns the filesystem and clock half — both are
forbidden inside `sim/`, which is why it lives in `game/` next to `TickPump`. It
detects change by **content digest**, not modification time, so two saves in the
same second are not mistaken for one. `Main` polls it and queues the result.

**The reload is an Input Action**, `InputAction.Kind.RELOAD_DEFINITIONS`, not a
method on the façade. It therefore goes through `step`, is ordered with every
other intent, lands in a recorded script, and replays exactly. The façade is
still three things.

What that buys, and what every later ticket may rely on:

- A reload **changes the state hash** at the tick it is applied. The definition
  digest and a reload generation counter are both hashed.
- A reload is **not undoable**. Reloading the original files does not restore the
  earlier hash, because the Run did change.
- A reload that **failed to load is refused** — so is one with no payload, and
  one whose declared digest disagrees with the set it carries. A refusal leaves
  the definitions and the generation counter untouched and the Run running. A
  typo mid-edit must never take a Run down.
- A `ReplayRecording` carries the **digest of the definitions it was made under**.
  `verify` compares that before it compares a single tick and reports
  `definitions_mismatch` — so a fixture cannot quietly pass against content that
  has since changed, and a content change is never misreported as a tick
  divergence. Leave `definitions` null in a fixture and the replay re-reads
  `content/`, which is what makes that check bite.

In co-op this is the Host's intent broadcast like any other, and the digest is
what lets a client whose own files hash differently refuse instead of desyncing.

## The grid, the Map and Machines

`sim/world_grid.gd` owns what the grid *is*; the Simulation owns what is on it.

- Tiles are `Vector3i` and 2 m across, per `docs/DESIGN.md`. Building is flat, so
  only layer 0 is buildable — that is `VERTICAL_BUILDING_ENABLED` and the layer
  range it governs, in one place, so discrete floors are a flag rather than a
  rewrite. A 4 m storey height is already reserved above the ground.
- A footprint is anchored at a tile and grows along +x and +z. **Its size comes
  from `content/machines.csv` and from nowhere else** — the Simulation, the
  renderer and the Blender mesh generator all read those same two columns, and a
  second copy would drift on the first balance change.
- `sim/map_layout.gd` is the Map's **starting** geography: where the Nodes are, what
  Resource each yields, what Depth tier it sits at, where the Nest stands, where the
  Breaches a Run *opens* with are, and where the Hives stand. Where the Breaches are **now** is Simulation state,
  because deep mining opens more — see the Depth section. Deliberately *not* in `content/` —
  those files are definitions and hot-reloadable, and moving a Node under a
  Factory that is standing on it is a different Map, not a balance change.
- **Nodes never deplete.** There is no quantity on a Node and nothing subtracts
  from one. DESIGN.md decided that: a 40-hour Factory must never need relocating,
  so Depth gates value instead.
- A Miner's input is the ground under it. It produces only while its footprint
  covers a Node whose Resource its Recipe produces, and otherwise accumulates no
  progress at all — a Miner on bare rock is visibly idle rather than invisibly
  banking time.
- A Machine is placed by an Input Action, `InputAction.Kind.BUILD_MACHINE`, which
  carries the Machine's definition *index* because an intent on the wire is
  integers. The Simulation stores the resolved *id*, so a hot-reload that resorts
  the table cannot renumber a Factory that is already standing. A build onto an
  unbuildable tile or an occupied footprint is refused as a silent no-op: a
  misaimed Build Gun is an ordinary thing for a player to do, and the hash does
  not move.
- A Machine does not run on the tick it was built, because it was placed during
  that tick. One craft takes a whole number of ticks, floored from the Recipe's
  seconds, minimum one, and progress is counted in ticks so nothing rounds away
  over a long Run.

## Belts and the Items on them

The most performance-critical system in the project, and the one whose data layout is
hardest to change later. The reference implementations of this genre spend the large
majority of a late-game frame on Belts and their Items, so this is built as integers in
arrays, never as an object per Item.

- **An Item is a position and an id.** Per Belt: one `PackedStringArray` of Item ids and
  one `PackedInt64Array` of positions, ordered front first. There is no Item class, no
  Item instance and — per ADR 0002 — no node: Items are derived state, recomputed
  identically on every client rather than replicated, which is why they cost no
  bandwidth. They are still **hashed**, because "identical everywhere" is worth nothing
  unchecked.
- **Positions are sub-units, not metres.** A sub-unit is sized so an Item advances
  exactly one per tick, so a saturated Belt delivers one Item every
  `ticks_per_item` ticks *exactly*, with no rounding anywhere and nothing emergent from
  frame timing. Metres appear only in `query_belt_item_position_metres`, which divides
  once at the end — that is what keeps a 500-tile Belt's far end at 1000 m rather than
  999.98 m.
- **A Belt's rating is data**: `belt.items_per_second` and `belt.items_per_tile` in
  `content/tuning.toml`. Speed and spacing are *derived* from those two, so there is no
  second number to disagree with them. Pick a rate that divides 60; one that does not is
  floored to whole ticks.
- **Back-pressure is not a special case.** Each Item advances one sub-unit unless the
  Item ahead — or the end of the run — is in the way. A full destination refuses a
  hand-off, the leading Item stops, and the queue packs at its spacing behind it. The
  queue a player sees is literally the state.
- **Belts connect by adjacency, and nothing else.** A Belt's run starts on the tile past
  a Machine's footprint edge (its output port) and ends pointing at another footprint
  edge (an input port) or at the *entry tile* of another Belt. No inserter entity exists
  (DESIGN.md), there is no stored connection to go stale, and side-loading onto the
  middle of a Belt is deliberately not a connection.
- **`content/machine_ports.csv` is read and drawn, and is still not the Simulation's
  *authority*.** #19 added the file and the mesh markers that match it, declaring an exact
  edge and tile for each port, and until #36 nothing in the game read a line of it — so a
  player was shown none of it and found out which face of a Smelter takes ore by building
  it wrong. `sim/machine_ports.gd` now loads it and answers, for a Machine at a tile turned
  any of four ways, which tile each port presents, which way it faces and where a Belt
  would dock; `Definitions` loads it as the one **optional** table and the renderer draws
  an arrow on every port of every Machine standing and of the one the hologram is about to
  land. What has *not* changed is the rule: `_load_from_port` and `_hand_off` still take
  any footprint edge tile, which is looser than the declaration.
  - **Why the file loads at all now.** Its own documented rule is "machine_id must name a
    row in machines.csv", and the table still describes bodies `machines.csv` does not
    define — `press_mk1`, `assembler_mk1`, `generator_mk1` — plus the Nest's delivery port
    and a Belt's own two ends, neither of which is a Machine. So the loader **keeps** a row
    naming no Machine rather than refusing the file: `ports_of` never finds it, because
    nothing asks about a Machine that does not exist. That looseness is the price of
    showing the player anything, and it is the clause to tighten on the day a declared
    port is a rule — a port declared for a Machine nobody defined is a typo worth refusing
    then.
  - **It is deliberately not in `Definitions.digest()`.** The digest is the set of numbers
    a Run is playing by, which a lockstep client checks it agrees with the Host about. The
    ports are read by the renderer and by nothing in the Simulation, so a client whose
    table differs draws different arrows and simulates the same Run.
  - **Open, and now a smaller ticket than it was:** tighten `_load_from_port` and
    `_hand_off` to the declared edge, tile and direction, and add the ports to the digest
    on the same day. It is a behaviour change with a balance consequence — every Factory in
    every fixture docks wherever it docks today, and the Turret has no row in the ports
    table at all — so it wants its own ticket and its own balance pass, not a corner of
    somebody else's.
- **A Belt is not a Machine.** No row in `content/machines.csv`, no Recipe, no `role`.
  GLOSSARY.md keeps the two apart and so does the code; `InputAction.Kind.BUILD_BELT`
  carries two tiles rather than a definition index.

### Laying one: press, drag, release

Until #36 a Belt was **one keypress stamping a fixed four-tile run** from the aimed tile
along the player's facing, and the code called itself a stopgap. A factory game lives or
dies on how it feels to lay a Belt, so this is the part of building that got the most
attention.

- **The route is the unit of intent.** `sim/belt_route.gd` is pure arithmetic over tiles —
  an L: a run along one axis, a corner, a run along the other — and it is shared by the
  three callers that must never disagree: the refusal projection, the apply, and the
  renderer drawing the preview. A route computed three times is three chances to disagree
  on the frame it matters.
- **The first run stops one tile short of the corner.** A Belt hands its Items to the Belt
  whose run *starts* on the tile past its own far end, so the corner tile has to be the
  second run's entry rather than the first run's exit. Getting that off by one lays two
  Belts that look joined and are not, which is why the arithmetic has exactly one copy.
- **One corner per drag, and a zigzag is two drags.** A general path is a path the player
  did not draw and has to inspect before committing.
- **`BUILD_BELT` grew a seventh argument rather than being replaced.** It is the corner
  axis, and an absent one reads as 0, so every recorded script and every fixture written
  when a Belt was a straight run still means what it meant.
- **Two identical tiles are a drag that never moved**, which is one tile of Belt aimed
  along the player's own facing — authoritative fixed-point state the Simulation already
  holds, read the same way by the apply and by the projection, so the preview cannot point
  one way and the Belt another. The argument `PAINT` makes for carrying no aim at all.
- **It lands whole or not at all.** `_belt_route_refusal` is consulted over every tile
  before the first Belt appears, in the shape `_build_refusal` already had, and
  `query_belt_route_refusal` reports the same function to the preview. A route half-laid up
  to the first obstruction is a player demolishing what they did not ask for.
- **The drag anchor is a device reading in the controller**, in the same category as the
  mouse buffer and the sprint latch: the route is *decided on release*, it crosses as one
  intent, and a replay reproduces the route without reproducing the mouse travel that aimed
  it. `test_recorded_session` drags one out with the corner flipped half way through and
  asserts, beside the replay, that two runs at right angles really did meet end to end.
- **DESIGN.md puts Belt routing on the menu side of its diegetic line**, with the things
  done hundreds of times rather than with the Silo's dial. A press-drag-release with a
  previewed route is exactly that: fast, repeatable, and nothing to transcribe.

**Open: a Belt still costs nothing**, so the HUD's route line reads "free". `content/tuning.toml`
says in as many words that the ticket giving Belts a cost should give Walls one at the same
time, in whatever table ends up owning both; the length is the number a player actually
decides on and it is on screen before the release.

### The update order, and the bias it avoids

Advancing Belts in index order would make a line's throughput depend on the order it was
built in: a Belt advanced before the Belt it feeds sees an occupied entry slot, one
advanced after sees a vacated one. That is a real desync risk and a real gameplay
inconsistency, so index order is not used.

Each tick walks the Belts **downstream first** — a Belt is advanced only after the Belt
it hands Items to. Each Belt feeds at most one other, so the order is found by chasing
each chain to its end and recording it backwards, starting chains in **canonical tile
order** (the tile a run starts at), which is geography rather than history. A Belt loop
has no downstream-most member, so the cycle is cut at its canonically first Belt and that
one join carries a tick of latency. Where two Belts merge, priority goes to the lower
tile, not the earlier build.

The order is derived, so it is rebuilt rather than hashed, and only when a Belt is laid.
`tests/cases/test_belts.gd` asserts the absence of the bias directly, by building the
same Factory in two orders and comparing every Item position tick by tick.

### A line that branches, and the rotation that makes it one

#46. **Loading a Belt from a Machine port is a pass of its own, after every Belt has moved**,
because a branch is decided at the Machine and not at the Belt. A Machine's output buffer is one
pot and each Belt takes at most one Item a tick, so two Belts off one Machine *compete* —
and deciding that competition inside `_advance_belt` meant deciding it in the order the Belts
happened to be advanced in, which is the one order this section is at pains not to let anything
depend on.

**The two halves meet on exactly one tile, and the order between them is deliberate.** A Belt fed
by a Machine port is usually not fed by another Belt as well — the tile behind its entry is a
Machine footprint tile or it is not, and `_hand_off` checks for a Machine before it checks for a
Belt. But two runs pointing different ways *can* land a hand-off on that same entry, and then one
of the two is refused. Loading last means the **upstream Belt gets the slot**, which is the right
way round rather than an accident: an Item on a Belt has nowhere else to go and backs the whole
line up behind it, where a Machine's output buffer is uncapped and banks the surplus safely.
Before #46 the port cut in and stalled the line feeding it, and
`test_an_item_already_on_a_belt_beats_a_machine_port_for_the_same_slot` is the pin on the new
rule. Everywhere else, #46 moved every Factory in every fixture onto a new code path and changed
what exactly one of them did.

- **The rotation is one integer per Machine, `_machine_port_cursor`, and it is hashed.** Which of
  its Belts a Machine gave first claim to last. One more parallel per-Machine array, indexed
  exactly like `_machine_progress_ticks`, so a Machine with no Belts off it carries a 0 nothing
  reads — and giving branching its own index space is how a branch would stop being a property of
  a Machine.
- **The cursor indexes the Machine's Belts in *canonical* order, which is what keeps the
  fairness free of the bias above.** The list is geography — by the tile each run starts at — and
  the cursor is the only history in it, so a share cannot depend on which branch was laid first.
  `test_a_branch_splits_the_same_way_whichever_belt_was_laid_first` is the same two-Factories
  assertion the update order has, pointed at a branch.
- **A blocked branch is skipped, not waited on.** A Belt with no room at its entry simply fails
  to take and the Item is offered to the next branch, so one full branch never starves the other.
  And the cursor moves to one past whichever branch actually *got* the first Item rather than past
  the one that merely had first claim — a branch that was blocked did not have its turn, so it
  does not lose it.
- **What two full branches cannot carry banks in the Machine**, whose output buffer is uncapped,
  which is where a player reads the surplus off. Nothing is destroyed because a Belt filled up —
  the rule a full input buffer already obeys.
- **Scarcity is the whole of what the rotation is for.** A Machine producing faster than its
  branches can carry serves all of them every tick and the cursor changes nothing. A Machine
  producing one Item every ninety ticks — which is every Miner the shipped content can build —
  alternates them exactly.
- **The canonical order is cached, not sorted per tick.** It falls out of the same rebuild that
  produces the downstream-first order, under the same staleness flag, because that rebuild
  already sorts the Belts to decide where to start each chain. This is the hottest loop in the
  project and a per-tick sort of every Belt in a late-game Factory is not a thing to add to it.

**One fixture's premise changed and is worth knowing about**, because it is finding 8's third
consequence arriving as a behaviour change rather than as a number.
`test_power.test_determinism_the_factory_losing_its_fuel_really_did_cross_into_deficit` lays a
second Belt off a Coal Miner to divert its fuel, and before #46 that diversion was a **cut** —
the Boiler never saw another lump and the grid settled on the 300 kW baseline for good. It is now
a **share**: the Boiler is fed about 20 lumps a minute against the 30 it burns, so it goes out,
relights, and goes out again. The fixture still crosses the line in both directions, which is
what it is for, so what the test asserts moved from the last tick's reading to a count over the
window — because which side of a flicker the last tick lands on says nothing about whether the
Factory lost its fuel.

### Machines, ports and starvation

- A crafter's inputs live in an **input buffer** separate from its output buffer, with a
  capacity of `machine.input_buffer_crafts` crafts' worth of each input. That capacity is
  the thing back-pressure pushes against.
- A Machine **banks no progress while starved**. It accumulates ticks only while holding
  a whole Recipe's worth of inputs, and consumes them when the craft completes.
  `query_machine_is_starved` answers the question for both roles — a Miner is starved
  over the wrong ground, a crafter over an incomplete buffer — so the renderer never has
  to infer it from a count that stopped moving.
- A tick runs **Belts before Machines**: an Item delivered this tick is usable this
  tick, and an Item produced this tick is collected on the next, which is the same rule a
  freshly built Machine follows.
- **Two Belts off one Machine is a split, and that is #46.** A line that branches is a factory
  game's second verb after laying a Belt, and until #46 this game did not have it: Belts were
  loaded one at a time inside `_advance_belt`, so the Belt whose entry tile came first took
  every Item and the second got only what the first had no room for. That was a *priority*
  rather than a share, and three measured Factory facts fell out of it — the sharpest being
  that **a second Belt off the shipped Smelter never received a single plate**, because the
  Ammo Press took the lot. See the branching section below, and finding 8 under "The joint
  balance pass" for what it cost before it was fixed.

## The one Power grid

One grid, no topology. Total supply against total demand, globally — no wires, no
sub-networks, no distance, and nothing in `sim/` that looks like a graph. That is
GLOSSARY.md and DESIGN.md, and it is the whole model.

- **A shortfall throttles every Machine by the same proportion.** Nothing is halted
  and nothing is singled out, which is what makes a brownout read as the Factory
  sagging together rather than as one Machine mysteriously dead. A Belt running out
  of a throttled Miner visibly thins, and that is the gauge a player reads first.
- **The throttle is a duty cycle over whole ticks, not a fraction of one.** Every
  tick the grid banks `min(supply, demand)` kilowatt-ticks and spends `demand` to buy
  the whole Factory one tick of work. On a grid supplying 1 against a demand of 3
  that buys a tick every third tick — exactly a third rate, with the remainder
  carried in an integer rather than thrown away. Over any window a Machine has
  advanced exactly `floor(ticks * supply / demand)` ticks: **one floor, applied once
  to the total, never once per tick.** A fixed-point ratio added up every tick would
  lose up to 2⁻¹⁶ of a tick each time and leave a 40-hour Factory quietly
  under-producing, so there is no fixed point in the mechanism at all.
- **`query_power_ratio` is for the gauge and the Simulation never reads it back.**
  It is the one place Power touches fixed point and it floors, so a third reads as
  0.33332…. Because the throttle is driven by the two integers instead, that rounding
  cannot reach the state hash or move a single Item.
- **Demand counts a Machine only while it would actually work.** A starved Smelter is
  not consuming, so it is not on the grid: cutting a Belt lightens the load rather
  than browning out the Machines that are still fed. `_machine_would_work` is the one
  predicate behind what the grid charges for, what advances, and what a query calls
  starved — three answers that must never disagree.
- **A Machine either feeds the grid or draws from it, never both.** `role=generator`
  supplies `power_supply_kw` and must draw nothing; everything else draws and must
  supply nothing. A Machine drawing nothing is never throttled, which is what stops a
  brownout from throttling the very Boiler that would end it.
- **A generator is a crafter that makes nothing.** Its Recipe is its fuel and its
  burn time, and it has no outputs, because Power is not an Item and never will be —
  there are no fluids and no steam on a Belt (DESIGN.md). Which of `inputs` and
  `outputs` a Recipe must fill therefore depends on the role of the Machine running
  it, so that pairing is checked in `_check_machines_against_recipes` and the error
  names the Machine's row. All three generator classes GLOSSARY.md names — Steam,
  Electric, Exotic — are this one role, differing in fuel chain and failure mode,
  which are rows rather than code.
- **A generator that is half fed supplies half a generator, and that is how one coal Node
  pays for a Silo.** Supply is totalled over the Machines `_machine_would_work` says are
  working, so a Boiler holding no coal contributes nothing *this tick* and a Boiler holding
  coal contributes all 600 kW — which means a Boiler fed at two thirds of its appetite is
  worth two thirds of 600 kW averaged over time rather than being a Boiler that does not
  count. The shipped coal Node yields 40 coal a minute against a Boiler's 30, so it is
  **1.33 Boilers' worth of fuel**: split across two Boilers it is about 800 kW of average
  supply instead of 600, and 300 + 800 against the opening Factory's 660 is what leaves room
  for a Silo's 400. #26 read the same two numbers as "there is no second Boiler to be had"
  and recorded "Milestone 1 cannot power a Silo" as a finding; the arithmetic is a *rate* and
  not a count, and `artillery` in the balance harness is the Run that demonstrates it. **No
  number changed for this** — the Power was always there to be built toward.
- **`power.baseline_supply_kw` exists because the Factory would otherwise deadlock.**
  Machines are throttled by the grid, a Steam Boiler burns Belt-delivered coal, and
  coal needs a Miner: a Factory starting on nothing but its own generators could
  never turn the first wheel. The baseline is the Nest's own small plant, tuned to
  exactly one Miner and one Smelter, so the first Machine beyond the opening line is
  the moment Power becomes the player's problem.

## The Nest, the Breaches, the Waves and the Enemies

The threat, and the thing that makes a Run losable. `MapLayout` owns where all of it
is, because it is geography; `content/tuning.toml` owns the numbers, because they are
balance.

- **The Nest is not a Machine.** DESIGN.md lists it alongside Belt and Wall, outside
  the eight Machines: no row in `content/machines.csv`, no Recipe, no Power, and it
  cannot be built or demolished. It is a 4x4 footprint on the Map that obstructs
  building and Belts, with hit points from `nest.health`. **Its destruction ends the
  Run and nothing else does** (GLOSSARY.md).
- **A Run that ended stays ended.** `_run_over_tick` is set on the tick the Nest fell
  and never cleared, so `query_wave_number` freezes at the Wave that did it — which is
  what the Run-over report names — and a later ticket that lets a Nest be repaired
  cannot un-end a Run. Waves stop and Enemies stop; the Factory is deliberately not
  gated, because there is no build mode anywhere in this project.
- **A Breach never moves, and every Breach is known in advance**, which is the whole deal
  GLOSSARY.md strikes: it is fortifiable, and it could not be if it moved. The *set* does
  grow — deep mining opens more, telegraphed first, see the Depth section — but a Breach
  that exists is a Breach that stays where it is. `MapLayout.tile_precedes` is the one
  definition of the order they are held in, and Enemies are released in that order, so which
  Breach goes first is geography rather than the order somebody typed the rows in *or the
  order a player happened to dig in*. A Map with **no** Breach has no Waves at all — which
  is the geography `MapLayout.empty()` gives a test that is studying the Factory and not the
  threat.
- **The Wave schedule is derived from Heat, not counted down.** See the Heat section
  below. `content/waves.csv` owns what a Wave is made of, `[heat]` owns when it comes,
  and `[wave]` owns the three things that are not about Heat — the Telegraph, the spawn
  trickle, and what the lever pays.

### Enemies are array entries, never nodes

Per ADR 0001, and this is the decision the whole Enemy scale target rests on.
Idiomatic engine agents cap out around 150-250 before frame times collapse; instanced
array entries reach thousands. Milestone 1 ships twenty Crawlers **on the final
architecture** so that the Chaff tier switching on later is more array entries rather
than a rewrite. #11 added the Breaker and the claim held: a second kind is a constant in
`sim/enemy_kind.gd`, four tuning keys, a row in `content/waves.csv` and two `match` arms —
no second array, no second loop, and no node. **#16 added the Siege Hulk — a boss — and it held
again**, at the price the note promised: one more `if` in `_enemies`, one function, and the one
piece of state the other kinds do not have (which way it is facing) as **two more parallel
arrays rather than a class**. See the Siege Hulk section.

- An Enemy is an index into parallel `PackedInt64Array`s — serial, kind, position in
  fixed-point metres, health, spawn tick, bite cooldown, and the point it is facing. There is no Enemy class, no
  Enemy instance and no node. `WorldView` draws the swarm through one `MultiMeshInstance3D`
  **per kind** — three nodes since #38 gave each kind its own character mesh, bounded by
  `EnemyKind.KIND_NAMES` and created before the first Wave — and `test_world_view` asserts
  that the scene tree does not grow by a single node when a Wave arrives.
- **Index order is ascending spawn serial, always.** Spawns append; `_enemy_serial`
  rises strictly with index. Every loop over Enemies therefore walks them in the one
  order every client agrees on. The purity lint catches a float; it would never catch
  an ordering bug, so `test_enemies` asserts the invariant directly on every tick of a
  Wave.
- A **serial** is issued once and never reused. That is the handle to hold rather than
  an index, because indices shift as Enemies die — which is what a Turret needs to
  keep shooting at the thing it was shooting at.
- Enemies do not collide with one another, by design. A swarm is a swarm, and the
  alternative is an O(n²) separation pass the Chaff tier could not afford. Nothing in
  an Enemy's tick reads another Enemy, so index order carries none of the bias Belts
  have to avoid.
- An Enemy does not act on the tick it came through its Breach, for the reason a
  Machine does not run on the tick it was built.

### Shared flowfields, not a path per agent

DESIGN.md calls this not a close call: rebuilding one field is O(map) once and is then
amortised across every Enemy alive, where per-agent A* is O(agents × path) every time
anything moves — and every Enemy converges on the same destination.

- `_flow_direction` holds a `WorldGrid` direction per ground tile, `_flow_distance` the
  exact tile count to the Nest, both as flat arrays indexed by tile. One breadth-first
  sweep outward from the **whole Nest footprint**, four-connected, so no heuristic is
  involved and an Enemy heading for the Nest's near edge is not routed to its anchor.
- **There are two fields, not one**, since #11: `_machine_flow_*` is the same sweep seeded on
  every Machine's footprint instead, and it is what a Breaker steers by **once it has broken
  ranks** (#34 — see below). Two destinations,
  two fields, one `_sweep` and one `_mark_obstructions` pass shared between them — because a
  field is the right structure for the second destination for exactly the reason it was right
  for the first. "Walk at the nearest Machine" is O(Breakers x Machines) every tick and a path
  to re-find every time one falls; a second O(map) sweep is paid only when the obstructions
  move. The seeds are themselves obstructions, so the sweep starts *on* them at distance 0 and
  only the expansion checks for a block, which is how a tile beside a Machine comes to point at
  it while nothing routes through it. An empty Factory leaves that field empty and
  `_enemy_direction` falls the Breaker back onto the Nest's, which is why a Breaker with
  nothing to break is still an Enemy at the gate.
- **A Breaker marches with the Wave before it hunts, and that is #34's whole decision.** It
  steers by the *Nest's* field — the road every Crawler walks, and the road a player
  fortifies — until it is within `enemy.breaker_breaks_ranks_within_tiles` of either the Nest
  or a Machine, and by the Factory's field from that tile on. Before it, a Breaker took
  whichever line was shortest to a Machine from the moment it emerged, which on a real Map is
  never the lane a player defended: #26 measured the documented opening Factory with *no answer
  at all* to the Breaker tier while an identical build with its second Turret over the Factory
  lasted nine minutes longer. A rule a player cannot see is a trap rather than a lesson. Three
  things make the fix cost almost nothing:
  - **Two array reads, no third field.** `_flow_distance` and `_machine_flow_distance` are both
    swept already, so "is the Nest at hand" and "is a Machine at hand" are integer comparisons
    against arrays that exist. Nothing new is rebuilt and the 2.5 ms sweep is untouched.
  - **It latches**, in one more parallel array — `_enemy_broke_ranks`, hashed, 0 for ever for a
    Crawler and a Siege Hulk. Latching is not an optimisation: a Breaker that has turned on a
    Machine walks *away* from the Nest, so a predicate re-decided every tick would cross back
    over the boundary on its first step and shuffle there for good. It is also the right thing
    to say about a Breaker — once it has chosen, it commits, and the turn is something a player
    watches happen.
  - **The second clause is load-bearing, not a special case.** Without "within reach of a
    Machine" the rule says something stupid on a Factory built nowhere near its Nest: the
    Breaker walks the length of the line, past everything in it, to the Nest's doorstep, and
    then walks all the way back. With it, a Breaker lunges at the first thing it can reach from
    the road it is on — which also makes **what a player puts beside the lane** the thing that
    gets eaten first, starting with the Turret standing in it. `test_machine_mortality`'s
    `_open_layout` moved its Nest onto the Breach's own latitude for this reason, and says so.
- **Derived, so it is rebuilt rather than hashed**, exactly like `_belt_update_order`.
  It is a pure function of the Map and the obstructions standing on it, both of which
  are hashed. Rebuilt when a Machine is built or demolished or a reload could have
  resized a footprint — never on a tick that changed neither, and never at all while
  no Enemy is on the Map.
- **`_mark_obstructions` is the single definition of what obstructs**, and
  `query_tile_obstructs_enemies` reads what it painted rather than asking the question
  a second way. Machines obstruct; Belts and Nodes do not — a Crawler crawls over a
  conveyor. **Walls joined it in #11, as one more loop** and nothing else, which is what that
  promise was worth.
- It paints by walking the **Machines**, not by asking each of the 16641 tiles what is
  standing on it. That is O(Machines) against O(tiles × Machines), and it is the
  difference between a 2.5 ms rebuild and a 55 ms one — a three-frame hitch every time
  a player places something.
- The sweep walks **flat index space** rather than `Vector3i`, for the same reason:
  `FIELD_STEPS` mirrors `WorldGrid.DIRECTION_STEPS` so the recorded direction still
  means what `direction_step` says it means, and `test_flowfield` walks a 60x60 region
  of the field a tile at a time to prove the two orders agree.
- An Enemy on a tile the field cannot route **because it is standing inside an
  obstruction** — a Machine a player dropped on top of it — walks straight at the Nest
  instead. Without that, pinning a Crawler under a Machine would be a cheese rather than a
  defence. An Enemy on *open* ground with no route is a different case and gets a different
  answer: it chews what is in contact (see Mortality below), because a beeline there would
  send a swarm drifting through solid Walls.
- Measured: 0.10 ms a tick at 20 Enemies and 0.84 ms at 200, against a 16.67 ms frame.

### Open: the Nest's footprint has two authorities

`MapLayout.NEST_FOOTPRINT_TILES` and the `nest` row of `content/machine_bodies.csv`
both say 4x4, and the asset suite's cross-check only covers rows that
`content/machines.csv` declares — which the Nest never will, because it is not a
Machine. The art pass should teach the mesh generator to read the footprint from the
Simulation's constant, the way it reads a Machine's from `machines.csv`.

Its **height** went the other way and is worth copying: #30 needed it in the Simulation,
so `nest.height_metres` is tuning the Simulation owns and the asset suite cross-checks the
`nest` row's `body_height_mm` against it by name — the same treatment
`belt.deck_height_metres` gets. Two facts about the Nest are now checked across the two
tables and one is not.

## Turrets, and the keystone loop

The ticket where the game acquires a point. Production and threat existed separately
before it; a Turret is what joins them, and DESIGN.md's whole thesis rests on it —
**production is combat power, mechanically rather than thematically.**

- **A Turret is a Machine whose output is damage rather than an Item**, and that is the
  entire design. `role=turret` in `content/machines.csv`, a Recipe whose input is
  Ammunition and whose outputs are empty, and `_craft` advances it exactly as it advances
  a Smelter. The only thing the Simulation adds is *what happens instead of depositing an
  output*: `_fire`. **The Steam Boiler is the precedent** — `role=generator` is a crafter
  whose Recipe has no outputs because Power is not an Item, and a Turret is the same trick
  in the other direction because damage is not either. `produces_no_items()` is the one
  predicate both roles share, so the next role whose product is not an Item joins the rule
  rather than forgetting it.
- **There is no combat subsystem, and there is no Turret table.** The target serial and the
  last-shot tick are two more per-Machine arrays indexed exactly like `_machine_progress_ticks`.
  Giving a Turret its own index space is how a Turret stops being a Machine.
- **A Turret with no Ammunition does not fire.** Defence therefore costs *continuous*
  production and there is no build-once-and-walk-away. An empty magazine reads as
  `query_machine_is_starved`, because that is what it is.
- **A Turret with nothing in reach does not work**, so it is not on the Power grid, banks no
  progress and spends no round. That is one more clause in `_machine_would_work`, the single
  predicate behind what the grid bills, what advances and what fires. Deliberately *not*
  starvation: it has its Ammunition, it has no target.
- **A Repair Pylon is the same role with the other column filled in.** `content/machines.csv`
  gained a `repair` column in #11, and the rule the loader enforces is that a Turret carries
  **exactly one of `damage` and `repair`** — its output is damage or it is repair, never both
  and never neither. `MachineDefinition.heals()` is the predicate, `_mend` is what happens
  instead of `_fire`, and `_turret_has_work` is the one clause `_machine_would_work` consults
  for both, so a Pylon over a whole Factory is idle and off the grid by the same rule that
  keeps an MG Turret with nothing in reach off it. Two things make a Pylon's target selection
  different from a Turret's, and both follow from what it is aimed at: it holds **no target at
  all**, because a Machine is an *index* and indices shift the moment anything is destroyed
  where an Enemy serial never does — so `_mend_target` is a pure read, re-decided every tick,
  which is also the right behaviour because there is no reason to finish mending the thing you
  started on rather than the thing nearest death. And it mends **the most damaged thing in
  reach**, measured in hit points missing rather than as a fraction of health, because a
  fraction is a division and a division needs a rounding rule.
- **`range_tiles` and `damage` are columns in `content/machines.csv`**, not tuning, because
  that is what makes a **Cannon Turret a row**: it differs from the MG in those two numbers
  and its Recipe, and neither is named anywhere in `sim/`. `tests/cases/test_turrets.gd`
  adds one to the shipped files and asserts it reaches further, hits harder and spends two
  rounds a shot, with no code change at all.
- **A reach is compared squared.** `Fixed.sqrt` floors, which would put a Crawler exactly on
  the boundary in or out of reach depending on a rounding rule; multiplying both sides
  instead is exact integer arithmetic. The products stay far inside 64 bits — the Map is 129
  tiles across, so the largest squared distance is about 1.4e14 against a 9.2e18 ceiling.
- **A Turret measures from its footprint centre**, so turning a 2x3 Turret does not move the
  circle it covers.

### Target selection, and the one determinism bug this ticket could have shipped

**A Turret holds a serial, never an index.** Enemy indices shift the moment anything dies —
`_remove_enemy` closes the gap — so a Turret holding an index would silently switch targets
on another Turret's kill, and two clients whose kills landed in a different order would
diverge. A serial is issued once and never reused (#9), so it either names the Crawler it
was aimed at or names nothing. `_enemy_of_serial` resolves it with a **binary search**, which
is exact rather than approximate because `_enemy_serial` is strictly ascending with index.

Four rules make the rest of it reproducible:

1. **`_aim` is the only thing that acquires**, once a tick, before the grid is read.
   `_turret_target_index` is a pure read, because `_machine_would_work` consults it and
   `query_machine_is_throttled` consults that — a query that re-aimed a Turret would move
   the state hash by being asked a question.
2. **Acquisition walks Enemies in index order and keeps a strict improvement.** Index order
   is ascending spawn serial by construction, so two Crawlers exactly as far away hand the
   shot to the earlier spawn, on every client.
3. **A Turret keeps a live target in reach**, rather than re-deciding every tick and drifting
   between two Crawlers a metre apart.
4. **A kill removes its Enemy immediately**, inside the same `_craft` loop, and clears that
   serial off every Turret holding it. So a second Turret later in the loop finds its serial
   unresolvable, reports itself idle, and keeps its round for the next tick rather than
   spending it on a corpse — and `query_turret_target_serial` either names something alive or
   names nothing, which is what stops a save restoring the ghost of a Crawler.

### Readable at a distance

An acceptance criterion of its own, and the reason is triage: mid-Wave a player is looking at
the whole Factory from thirty metres and needs to know which Turret is about to stop. So
`WorldView` hangs a **gauge in the world over every Turret** — a dark backing bar at full
width and a coloured fill scaled to the fraction held, green above half and amber below.
Two meshes rather than one because an empty magazine must not be indistinguishable from a
Turret with no gauge: the **backing goes red when the magazine is empty**, so absence of a bar
means there is no Turret there. The bars are unshaded, because a gauge a directional light can
darken is a gauge a player misreads at the worst moment. The HUD says `ammo n/m` and `DRY`
alongside, for the post-mortem rather than the fight.

**A gauge hangs off its own Machine's roof, never off a constant.** The height comes from
`query_machine_height_metres` — the same number the Simulation collides against and the same
number a placeholder box is sized from — plus `AMMUNITION_GAUGE_LIFT_METRES`. It used to come
from a `MACHINE_GAUGE_HEIGHT_METRES` set "taller than any housing in the content", which is a
second authority on how tall a Machine is: it detaches the bar from everything that is not the
tallest, and #41 was the result — a dry 2.0 m Turret wearing its red backing 2.1 m clear of its
own roof, read as a saturated red rectangle floating over the Factory with no owner. Red is
load-bearing here, so a red mark with nothing under it is worse than no mark. The lift also has
to stay under `STARVED_MARK_LIFT_METRES`, which hangs off the same roof, or the amber starved
tag draws straight through the middle of the bar; `test_world_view` asserts both bounds.

### Where the balance stands

**These figures are measured, not derived.** `tools/balance/measure.sh` plays scripted
sessions headless to the end of the Run and reports what happened; the whole method, the
scenarios and every finding live under "The joint balance pass", below. Re-run it after any
edit to `content/` rather than reasoning about what the edit did.

Shipped Map, shipped content, three seeds, measured 2026-10-08 **with #46 in** — none of these
four rows has a Machine with two Belts off it, so #46 left every one of them exactly where #35's
schedule did:

| Scenario | Run | Wave | Peak Heat | What killed it |
|---|---|---|---|---|
| `bare` — builds nothing | 3m22s | 1 | 0 | undefended; the first Wave alone |
| `competent` — six Machines, one MG on the lane | **28m48s** | 35 | 6725 | a Siege Hulk standing, 96 rounds still in it |
| `fortified` — a second MG over the Factory itself | **28m45s** | 35 | 6716 | the same, 112 rounds unspent |
| `hive_sortie` — `competent` after clearing one Hive | **32m05s** | 39 | 6672 | the same, 3m17s later |

Nine times the Run an undefended Nest gets, and still lost.

**It no longer loses because it runs dry, and #34 is why.** Before it, a Breaker steered by the
Factory from the moment it emerged, so the documented Factory lost all five production Machines
to a tier its Turret could not reach — the Run ended at minute twenty-seven, dry, with the
Breakers finishing it. Now the Breaker marches the lane under fire, the Factory keeps its line
through the whole Breaker tier, and the Heat it goes on making carries it past
`siege_hulks.min_heat` — so what ends the Run is the **boss**, three Siege Hulks deep, with 96
rounds still in the Factory and the one answer DESIGN.md always said it had: a player on foot.

The Ammunition arithmetic is unchanged and is still worth knowing, because it is what the
*middle* of the Run is paid out of: the Turret fires four rounds a second and a Crawler takes
two of them, while one Ammo Press makes two rounds every three seconds — 37 a minute, so about
19 Crawlers a minute of killing. The Wave interval floors at 40 seconds, which is 1.5 Waves a
minute, so **one Ammo Press sustains about twelve Crawlers a Wave and no more**. What changed is
the *other* side of the ledger: with the production line surviving, the stockpile peaks at 454
rounds around minute twenty-four and is still 96 deep when the Nest falls. **One Turret cannot
spend what one Press makes**, which is a different and better problem to have than the old one,
and it is why the second Turret in `fortified` is now a wash rather than a two-minute gain.

**The measured way past thirty minutes is to walk out and clear a Hive**, which is the only
thing in Milestone 1 that moves Heat permanently: `hive_sortie` is 32m05s against `competent`'s
28m48s, and it is the longest Run the harness has recorded. A second Ammo Press is still the
*arithmetic* answer to the middle of the Run — production is the defence, in the most literal
form available — but since #34 the thing a one-Press Factory ends up short of is not rounds. It
ends with 96 of them. Both are buyable: the call-early lever pays
`wave.call_early_bounty_per_item` of each starting Item, and the Nest's store hands back
whatever a Belt banked. `test_nest_store.gd` proves that end to end; see the Nest's store, below.

Two things a later ticket should know:

- **A Machine's output buffer is uncapped**, so a Belt that fills up banks the surplus in the
  Ammo Press indefinitely. The stockpile a player builds between Waves is real and unbounded,
  and it is what carries the middle of the Run — it peaks at 454 rounds around minute
  twenty-four and is still 96 deep when the Nest falls.
- **A Turret on the Nest's lane now defends the Factory, and #34 is the whole of why.** A
  Breaker used to steer by the *Factory* flowfield from the moment it emerged, so it never
  walked into the reach of a Turret placed to cover the Nest — the `competent` Factory lost all
  five production Machines in its last minutes to a rule a player could not see. It now marches
  the Nest's own field until the Nest or a Machine is within
  `enemy.breaker_breaks_ranks_within_tiles`, so it arrives down the road, under fire, and turns
  on the Factory where a player can watch it. See the flowfield section, and "What #34 cost the
  table" below for the figures. The consequence for `fortified`'s second MG at (11, 6) is that
  it is no longer what answers the Breaker tier, and the two rows have converged.

## Mortality: what can be taken from you

The ticket that makes a Factory's layout a **defensive** decision rather than a logistics one.
Before it a Crawler walked past a Smelter; after it, where the Smelter stands decides whether
it survives the Wave. Three integer arrays carry the whole of it — `_machine_health`,
`_wall_health` and `_player_repair_credit` — in whole hit points with no fixed point anywhere,
which is what makes damage and repair replay identically.

### A destroyed Machine is gone, and nothing comes back

The one decision here worth arguing, and the asymmetry the whole mechanic rests on.
`_refund_machine` hands back a build cost, both buffers and the Items riding a Belt.
`_destroy_machine` hands back **nothing**, and removes the Machine rather than leaving a wreck.

- **A demolition is a player taking their own Factory apart; a destruction is the Enemy taking
  it.** If destruction paid out, a Machine about to fall would be better watched — or
  demolished for the refund — than rescued, and the repair mechanic this ticket is about would
  be strictly worse than doing nothing.
- **There is no player to pay.** A Machine ten tiles from anybody falls with nobody standing
  there, and "the nearest player" is not a rule a lockstep Simulation should want: it would
  make a refund depend on where four people happened to be.
- **The Items in it were real throughput.** A Smelter holding eight plates when it falls is a
  loss a player can feel and attribute, which is exactly what Heat asks of a mechanic.

Removal rather than rubble, for the same reason: a hole in a Factory's wall is a *hole*. The
Belt chain through it breaks because the Machine its run pointed at is not there, the
obstruction is gone so the next field rebuild routes Enemies straight through the gap, and
`test_machine_mortality` asserts both. **You repair the living and rebuild the dead** — repair
cannot touch a Machine that is already gone, and the Build Gun is how one comes back.

### The destruction happens mid-tick, and the fields do not

A Machine destroyed part-way through the Enemy loop invalidates both flowfields — it is one
fewer obstruction and one fewer seed. Rebuilding there would make the tick **O(Enemies x map)**,
which is the quadratic the Chaff tier could never pay, so `_enemies` resolves both fields
**once** for the whole tick and `_destroy_machine` only sets `_flowfield_stale`. The survivors
finish the tick on the field they started it on and inherit the gap on the next one. A tick of
latency on a route is invisible; a 50 ms hitch mid-Wave is not. `_tile_is_blocked` exists as the
half of `_tile_obstructs_enemies` that does *not* force a rebuild, for exactly that reason.

### What an Enemy bites, in three clauses

`_enemy_contact_target` answers it, and the order is the design:

1. **A Breaker takes a Machine over anything else.** That is the whole of what a Breaker is
   (GLOSSARY.md: it preferentially attacks Machines rather than players) and it is what makes
   mortality *felt* rather than merely true — a Crawler walking past a Smelter proves nothing
   about whether the Smelter was ever at risk. Once it has broken ranks (#34) it steers by the
   Factory's field too, so it is hunting rather than bumping into things — and **this clause
   fires whether or not it has**, which is deliberate: a Breaker still marching the lane eats a
   Machine a player put *on* the lane, because a Machine in its way is a Machine in its way. The sentence was read as "rather than the Nest"
   until #15 gave a player health, and it cost exactly what this note promised: **one more
   clause in `_enemy_contact_target`, ranked below a Machine**, and nothing else changed. A
   Breaker with a Smelter in reach still chews the Smelter with somebody standing next to it,
   which is what makes GLOSSARY.md's sentence literal rather than aspirational.
2. **Either kind bites a player it can reach.** #15's clause, ranked below a Machine and above
   the Nest — so standing in a doorway is a real way to buy the Nest time, at the price of your
   own skin. See the Gear section.
3. **Either kind bites the Nest it is standing at.** A Breaker out of Factory is still an Enemy
   at the gate, and the Nest is still the only loss that ends the Run.
4. **Either kind chews out of a pocket it cannot route out of**, Machines before Walls. Without
   it, sealing a Breach behind a ring of Walls would be a cheese rather than a defence. With it,
   sealing buys exactly as much time as the Walls have hit points — which is what a Wall is for,
   and what `test_sealing_a_breach_buys_time_rather_than_stopping_a_wave` asserts. An Enemy
   standing *inside* an obstruction is excluded and still beelines, which is #9's rule kept.

A Crawler with a route therefore still walks past a Machine untouched. Chaff is the sense of
threat; the Breaker is the threat. One consequence for later Enemy kinds: `_enemy_damage` is one
number per kind whatever it is biting — the Nest, a Machine or a Wall all just have hit points —
so adding an Enemy is four tuning keys and a `match` arm, never a table of multipliers.

### A Wall is not a Machine

DESIGN.md lists it alongside the Nest and the Belt, so: no row in `content/machines.csv`, no
Recipe, no Power, no ports, no buffers. `wall.health` in `content/tuning.toml` is its hit
points, tuning rather than a row for the reason a Belt's rating is.

- **One tile per intent**, unlike a Belt's run. A Belt is a run because Items travel along it
  and the run is the thing; a Wall is a tile because the only question it answers is whether
  *this* tile is walkable, and because a Wall chewed through in the middle of a line has to
  leave the rest of the line standing.
- **A Wall costs nothing to build, and there is deliberately no tuning key for a cost.** A
  build cost names an Item, the Items that exist are exactly the ones the Recipes mention, and
  `machines.csv` is where a cost sits *next to* that check. Naming one in tuning would couple
  the tuning file to the Recipe table from the other side of the content directory, and it
  broke every test that supplies its own Recipes when it was tried. The ticket that gives Belts
  a cost should give Walls one at the same time, in whatever table ends up owning both.
- `WorldView` draws them through **one MultiMesh**, with per-instance colour for health,
  because a Wall is the cheapest thing a player builds and a late-game maze is hundreds of
  them. `test_world_view` asserts the scene tree does not grow by a node for thirty of them.

### Repairing: a wrench costs attention, a Pylon costs material

The two halves of one trade, and they are deliberately priced in different currencies.

- **`InputAction.Kind.REPAIR` is held, not an edge**, and carries a tile. `_repair` consumes
  and clears the intent every tick, so a player who stops sending it stops repairing and the
  per-tick arrays are zero at every point a hash is taken — the same arrangement the walking
  throttle has. Hand repair spends **no materials at all**: what it costs is a player standing
  next to the Machine, in the open, during a Wave, doing nothing else. That is what makes melee
  useful rather than a last resort (DESIGN.md: the Pneumatic Wrench is the melee weapon and it
  is also what repairs). Nothing gates it on a Wave in either direction, exactly as nothing
  gates building.
- **The rate is an integer credit against `TICKS_PER_SECOND`**, carried in
  `_player_repair_credit`, so over any window a Machine has gained exactly
  `floor(ticks * points_per_second / TICKS_PER_SECOND)` — one floor applied to the total, never
  one per tick. #7's lesson, applied again. Credit does not survive letting go or walking out of
  reach, the same rule Power credit and Heat credit obey.
- **Reach is compared squared**, like a Turret's, because `Fixed.sqrt` floors and a player
  exactly on the boundary must not be in or out by a rounding rule.
- **`query_repair_refusal` is a projection about a repair that has not happened**, the same
  arrangement `query_build_refusal` has: the HUD says "out of reach" or "already whole" while
  the player is still walking over, and a refusal leaves the hash alone. `Refusal.OUT_OF_REACH`
  and `Refusal.NOT_DAMAGED` are the two new reasons.
- **A Repair Pylon is a Turret** — see the Turrets section above for the `repair` column, the
  exactly-one-of rule, and why it holds no target.

### Where the mortality balance stands

`enemy.breaker_damage` is 60 a second against a Smelter's 500, so a Smelter under one Breaker
has nine seconds to live. `wrench.repair_points_per_second` is 60, so **one player with a
wrench exactly holds one Breaker off** — `test_machine_mortality` asserts it, and it is a
coincidence of two tuning values rather than a designed identity. A Repair Pylon pulses 40 a
second and spends a plate doing it, so it loses to a Breaker on its own and beats a Crawler
comfortably.

**#26 moved the Breaker threshold and the measurement says why.** At
`shock_breakers.min_heat = 500` a producing Factory passed it at about two and a half minutes
— before a player has any second Turret to cover the Factory with — and the Breakers
quietly dismantled all five production Machines from minute three onward, leaving a Run that
spent its remaining ten minutes as one Turret firing a dwindling stockpile at Chaff. It is now
**5200**, which the documented opening Factory reaches at around minute twenty-two.

**#34 then answered the question #26 left the threshold open for, and answered it differently
than #26 expected.** The question was *is your Turret covering the Nest or the Factory?* — and
the trouble with it was that a player could not see it being asked, because a Breaker never came
within reach of either answer except by accident. The fix was not a second Turret but a change to
where a Breaker walks: it marches the Nest's own field until the Nest or a Machine is within
`enemy.breaker_breaks_ranks_within_tiles`, and hunts from there. So the question a Breaker asks
now is *is the road covered, and is the Turret on it fed?* — which a player can watch being asked
and answered. See the flowfield section, the Turrets section, and "What #34 cost the table" under
"The joint balance pass" for the eight Runs it was measured on.

`wall.health`, `wrench.repair_points_per_second` and the Pylon's `repair` column were not
moved. They are priced against `breaker_damage`, which also did not move, so the relationships
`test_machine_mortality` asserts are unchanged; what changed is *when* a player is asked
about them. **Still unplayed by a human**: nothing in the measured scenarios picks up a wrench
to defend a Machine, because an open-loop scripted session cannot chase a Breaker. Hand repair
under fire is the one part of this ticket a harness cannot measure.

## Heat, the Wave schedule, the Telegraph and the lever

The mechanic that makes the game a game rather than a sandbox. Without it "infinitely
scaling" is an idle game — more production is self-justifying and costless. With it every
new Machine is a bet, because scaling up is simultaneously how a player gets strong and how
they get hunted (DESIGN.md).

- **Heat is made of completed crafts**, plus a term for the Depth of the Node a Miner is
  working. Deliberately not Power drawn and not Machines running. Heat has to be something
  a player can watch themselves cause, or the Waves read as bad luck and the mechanic
  teaches nothing: a craft is the one event in the Factory that is unambiguously
  throughput, that a player built the Machine in order to get, and that stops the moment
  the line starves. Power drawn would have made Heat a second reading of a gauge that
  already exists and would have charged a slow Recipe with a big draw more than a fast line
  that produces. A count of Machines running would have punished building rather than
  producing, and made a starved line exactly as hot as a fed one.
- **Heat is a whole number of units and there is no fixed point anywhere in it.** This is
  #7's lesson applied to the one quantity that accumulates for forty hours. The
  accumulator has two halves: **in**, a craft adds whole units at a discrete event, so
  there is nothing to round; **out**, the decay is quoted per minute and carried as an
  integer credit against `TICKS_PER_MINUTE`, exactly as the Power grid carries
  kilowatt-ticks. Over any window the Factory has shed exactly
  `floor(ticks * decay_per_minute / TICKS_PER_MINUTE)` — **one floor applied to the total,
  never one per tick.** `test_heat` asserts that with a decay of one unit a minute, which
  is 18 of 65536 in 16.16 fixed point and would lose 1% an hour if it were done that way.
- **The decay is flat, not proportional**, which is a design decision as much as a
  determinism one. A proportional decay is a per-tick ratio — the shape that drifts — and
  it would give the Factory an equilibrium Heat, which is the opposite of the point. Flat
  means Heat measures throughput *in excess of what the Nest can hide*, and that rises
  without bound as the Factory does. `heat.decay_per_minute = 0` is a legal value: a Map
  where Heat only climbs is balance, not a broken file.
- **The first gap of a Run is its own number**, `heat.first_wave_interval_seconds`, and
  everything else about it is identical: Heat shortens it, the minimum floors it, the
  Telegraph gates the arrival. The baseline used to double as the opening gap, which put the
  first Wave 150 seconds out and made #35's playtest report *"crawlers dont seem to be
  coming"* — they were, in silence, for longer than most people will wait, for the most
  interesting thing in the game. The opening gap is the **one interval a player has had no
  chance to shorten**: every later one is the Factory's own doing, and this one is spent with
  no Heat to spend it with. Shipped at 90 after measuring 50 and finding it too short — the
  figure and why are under "The joint balance pass", below.
- **The interval is derived every tick rather than stored**, so a hot Factory is hunted
  *sooner* and not merely harder — and sooner *now*. `_wave_elapsed_ticks` counts up and
  `_wave_interval_ticks()` is a function of current Heat, so switching a line on pulls the
  countdown towards the player on the tick they switch it on. A stored countdown could only
  ever have shortened the Wave after next, which teaches nothing. It moves both ways: a
  Factory that cools gets its breathing room back, which is what makes tearing a line down
  a real decision.
- **Every Wave passes through a full Telegraph, and that is a gate rather than a
  convention.** `_a_wave_is_due` checks `_telegraph_ticks_served` first and
  unconditionally, so a Wave cannot arrive until the warning has run its tuned length —
  including one a player called, and including one a sudden Heat spike left *overdue*. That
  last case is the hard one and the reason the gate is not a courtesy: Heat shortening the
  interval can put the arrival in the past, and without the gate that would be exactly the
  ambush DESIGN.md forbids. There is no audio yet, so the klaxon is a capitalised HUD line
  with a countdown and a gauge that fills.
- **The Telegraph names what is coming, not only that something is (#34).**
  `query_telegraphed_wave_count_of_kind` is a projection — every tier the Heat has reached,
  times every Breach — and `WorldView` prints it under the countdown as "6 crawlers, 2
  breakers". That is the legible half of #34: the geography fix brings a Breaker down the road
  under fire and turns it on the Factory when it gets there, which is a lesson a player can act
  on only if they knew a Breaker was in *this* Wave while there was still time to go and stand
  somewhere. Six Crawlers is a line to hold; six Crawlers and two Breakers is a reason to be
  somewhere else.
  - It is a **projection and not state**, read off the definition set and the current Heat
    rather than off `_wave_queue_kind` — that queue does not exist until `_begin_a_wave`
    composes it, and composing it early would *be* the Wave arriving. So it is a promise about
    the Heat as it stands, and a line a player switches on mid-Telegraph can still buy one more
    Crawler. That is #12's bet and it is correct to leave visible.
  - **Times the Breach count**, because `_release_from_the_breaches` releases one per Breach. A
    Map a player has dug a second hole in is attacked through both, and a warning that did not
    say so would under-report by half.
- **The lever waives the interval and nothing else.** What it buys the Enemy is nothing at
  all: a Wave is composed from the Heat the Factory is carrying when it *arrives*, so
  calling early means it arrives while that Heat is lower than it would have been. What it
  costs is the breathing room given up. One trade, no second number to tune. It pays
  `wave.call_early_bounty_per_item` out of the same stock the Build Gun spends, in the
  Items `player.starting_stock` names rather than in a count of every Item in the game. That
  changed with #14 for two reasons: the lever buys the means to *defend*, so what it pays is
  build materials; and a bounty paid in every Item would have conjured exactly the goods
  `content/deliveries.csv` asks for, so a player could have bought a Delivery tier off the
  lever without a Factory.
- **A refused pull is a silent no-op whose hash does not move**, and
  `query_call_wave_early_refusal` is a projection about a pull that has not happened — the
  same arrangement `query_build_refusal` has, and for the same reason: the reason is on
  screen before the player commits, which is the only version that leaves the hash alone.
- **Composition is `content/waves.csv`, and a Wave is every tier the Heat has reached** —
  not a choice between them. A hot Factory is sent the Chaff it was always getting *and*
  whatever its Heat has newly unlocked. Each row scales with how far past its threshold the
  Factory is, up to a `max_per_breach` that is a performance ceiling as much as a balance
  one: a Run left to cook for forty hours must not try to put a hundred thousand Enemies on
  the Map. Adding an Enemy to the Waves is a row.
- **`sim/enemy_kind.gd` is the one place a kind's name and its integer meet.** The table
  names kinds in words because a table a designer edits cannot be written in enum ordinals;
  `Simulation.ENEMY_KIND_*` are aliases of those constants rather than a second copy, so
  the file and the code cannot drift. A name no kind answers to is an error naming the row.
- **A Wave is composed once, when it arrives**, and the queue is then fixed. Otherwise a
  player who switched a line off mid-Wave would watch Enemies vanish from the queue.
- **Heat and its contributors are visible or the mechanic collapses into bad luck.**
  `query_heat` is the total; `query_machine_heat_units` is each Machine's lifetime
  contribution, which is hashed state rather than an estimate, and is what a player reads
  off the Machine they built. `query_heat_per_minute` and
  `query_machine_heat_per_minute` are **projections** and the Simulation never reads them
  back — that is where the division lives, in the same sense `query_power_ratio` is where
  Power's does. Power's duty cycle is deliberately not folded into the rate: the Heat line
  says what a Machine's Recipe is worth while it runs and the Power line says how often it
  runs, so each reading stays one fact.
- **A Map with no Breach freezes the whole Wave clock.** Enemies enter at Breaches and
  nowhere else, so a countdown that kept running would report a Wave that is never coming.
  Heat still accumulates, which is what lets a test study Heat without a Wave interrupting.
- **Building is still never gated**, mid-Wave or otherwise, and `test_heat` asserts it
  directly so that nobody adds a flag.

**The numbers in `[heat]` and `content/waves.csv` are measured, not guessed.** They were set
against played Runs in #26 and both files carry the reasoning inline; the method, the table and
the findings are under "The joint balance pass", below. Changing any of them is a
`tools/balance/measure.sh` away from being checked rather than argued about — and the four that
decide how long a Run lasts are `heat.decay_per_minute`, `chaff_crawlers.heat_per_extra`,
`shock_breakers.min_heat` and `siege_hulks.min_heat`.

## Depth, and the Breach greed opens

The mechanic that makes growth a *decision about the Map* rather than a decision about a
number. Deeper ore is richer, needs a better Miner, draws more Power and raises more Heat —
all of which a player could read as an upgrade with a price tag. What makes Depth different
is that extracting at it **rearranges the geography they have to defend**: a new Breach opens
near the mine. Reaching for better ore buys ground it did not ask for.

- **A Node's Depth is geography and a Miner's reach is data.** `MapLayout` carries the tier
  each Node sits at; `max_depth` in `content/machines.csv` is the whole of a Miner's tier, so
  `miner_mk2` and `miner_mk3` differ from `miner_mk1` in that column, their draw, their
  Recipe and their build cost — **and in nothing named anywhere in `sim/`**. A Mk4 is a row,
  exactly as a Cannon Turret is.
- **A Miner over ore it cannot reach is starved**, not halted and not throttled. One clause
  in `_machine_has_its_inputs` buys all three consequences at once, because
  `_machine_would_work` is the single predicate behind what the grid bills, what advances and
  what a query calls starved: the Miner draws nothing, banks nothing, and the HUD already
  says why. The same treatment a Miner on bare rock gets, for the same reason — a Machine
  doing nothing must be visibly doing nothing.
- **Power scales with the Machine, not with a flat surcharge.** `depth.draw_percent_per_depth`
  adds that percentage of a Miner's own quoted draw per tier past the first, so the cost of
  depth lands proportionally on a small Mk1 and a big Mk3 alike. Recomputed every tick from
  two integers in `_depth_adjusted_draw_kw` with **one floor applied to the result** — there
  is no accumulator here, so unlike the Power credit and the Heat decay there is nothing to
  drift. `query_machine_power_draw_kw` reports the very figure `_read_the_grid` totals, so a
  deep mine's brownout and the number explaining it are one fact.
- **Heat's Depth term is #12's and there is exactly one of it.** `heat.per_craft_per_depth`
  already charges a craft for the tier it came out of. A second surcharge added here would
  have made the gauge disagree with the arithmetic a player can do in their head, which is
  the entire value of Heat being made of countable crafts. `test_depth` asserts the existing
  term rather than duplicating it.
- **Sustained extraction opens the Breach, counted per Node.** `_node_deep_crafts` counts
  crafts at `depth.breach_tier` or deeper against the *Node*, not the Miner — the hole in the
  ground is what did it, so demolishing the Miner and rebuilding is not a way to reset the
  count, and the Breach is attributable to the mine a player chose to open. One Node opens at
  most **one** Breach ever (`_node_breach_opened`), which is what bounds the mechanic: a
  forty-hour Run cannot ring itself with a hundred holes. The cap being per Node rather than
  per Run is what keeps the *second* deep mine a real decision too.
- **A new Breach is telegraphed before it first spawns, and that is a gate.** It is announced
  into `_pending_breach_*` and only joins the Map once `depth.breach_telegraph_seconds` have
  been served — longer than a Wave's Telegraph, because the answer to a new Breach is a
  Turret and a Belt rather than standing somewhere different. A pending Breach does not spend
  its first tick of warning on the tick it was announced, which is why
  `_pending_breach_announced_tick` is held: the rule is explicit rather than an artefact of
  where `_breaches_open` sits in `step`. `WorldView` marks the tile on the ground in a
  *different* colour and shape from a real Breach — "a hole is about to appear here" and
  "there is a hole here" ask for different things — and the HUD raises a klaxon that names
  the tile, because unlike a Wave the only useful response is to go and look somewhere new.
- **Where it opens is arithmetic, never an RNG draw.** The first valid tile on the ring
  `depth.breach_offset_tiles` out from the Node, walked in canonical tile order, which in
  practice is the ring's north-west corner. Predictable twice over: a Breach is only
  fortifiable if a player can plan for it, and geography that consumed an RNG draw would make
  *which* Breach you got depend on how many draws the Run had spent. The ring widens by up to
  `RING_SEARCH_WIDENING` if every tile is taken, and a Map with nowhere to put one simply
  does not get one — that is geography, not an error.
- **The flowfield is not rebuilt, and that is the point rather than an omission.** The field
  is a pure function of the Map's ground and the Machines on it; a Breach is neither, because
  it does not obstruct and is not a destination. Every ground tile already has a direction and
  a distance, so the tile a new Breach opens on is already routed and an Enemy out of it
  steers by the same shared field. `_breaches_open` therefore never touches
  `_flowfield_stale`, and `test_depth` asserts that every tile sampled routes exactly as it
  did before the opening.

### The determinism trap, and where the line between Map and Simulation sits

`MapLayout` sorts Breaches into tile order and `_release_from_the_breaches` walks them in
index order, so Enemy release order — and therefore which serial belongs to which Crawler —
is geography. **Appending a runtime Breach would quietly change that to "the order a player
dug in"**, and two clients whose Miners completed a craft in a different order would then
disagree about which Crawler is which. `_insert_breach` is the only way anything joins that
array and it inserts at the position `MapLayout.tile_precedes` names, so the invariant holds
by construction. `test_depth` asserts the array is still ascending afterwards, and that
digging two mines in the opposite order produces the same Map — both of those fail if the
insert is changed to an append.

The line between the two owners is drawn at *starting* versus *live*:

- **`MapLayout` owns the opening geography and the canonical order.** It is authored, it is
  not hot-reloadable, and it is identical for every Run on this Map. It gained a static
  `tile_precedes` — the single definition of tile order, now used by Node sorting, Breach
  sorting and the Simulation's insert, so there is one comparator rather than three.
- **The Simulation owns the live Breach set and everything that produced it.**
  `_breach_tile_*` was already copied out of `MapLayout` and hashed (#9 made it an array
  deliberately), so no state *moved* — what changed is that the array is no longer constant
  through a Run. `_node_deep_crafts`, `_node_breach_opened` and the five `_pending_breach_*`
  arrays joined it. All of them are hashed; none of them needed a line in `sim/run_save.gd`,
  which reflects over the property list.

## The player, the Build Gun and Survey View

A player is 1.8 m against 2 m tiles, and every single thing they do crosses into the
Simulation as an Input Action. The controller holds no authoritative state.

- **Position, facing, velocity and the camera are Simulation state**, in fixed point.
  `game/` asks `query_player_*` where to put the camera; it never decides. Yaw is in
  **turns**, not radians — radians need PI and PI is a float — and `Fixed.sin_turns` /
  `cos_turns` read a 65-sample quarter-wave table, exact at the quadrant boundaries and
  within `Fixed.SIN_TOLERANCE` everywhere else.
- **`MOVE` is a throttle in the player's own frame**: forward and strafe, which the
  Simulation rotates by the yaw it is holding. There is therefore no second copy of the
  facing angle for the controller to rotate WASD by. Intent is **per tick**; sending no
  `MOVE` is how a player stands still, so an idle tick is a tick spent slowing down.
- **`LOOK` carries pixels, not an angle.** The sensitivity that turns pixels into a turn
  is tuning the Simulation owns, exactly as it owns the walking speed, so a client cannot
  turn faster by sending a bigger number.
- **Walking has acceleration**, so a person has weight. Velocity is state and is hashed.
  See "Weight" below for what #29 made of that, which is most of it.
- **Survey View is held, not toggled**, and its transition is counted in ticks *inside*
  the Simulation, eased on the way out with `Fixed.smoothstep_fixed`. That is a decision
  about feel rather than about determinism: its height, duration and tilt are
  hot-reloadable tuning, and the only way to find out whether a lift feels good is to try
  several. **It is not a mode** — nothing consults it to decide whether an intent is
  allowed, and a player can walk and build while surveying.
- **Building is never gated.** There is **no check anywhere in the Simulation that asks
  whether building is currently permitted** (GLOSSARY.md: the Build Gun is available at all
  times, including mid-Wave). #29 added a `_player_build_mode` flag and did not weaken that
  sentence by one word — see "Build mode is a hand, not a gate" below, and note that no
  refusal, no build path and no `_fight` reads it.

### Weight: jumping, the four accelerations and the camera's response

#29's half of the player, and it came out of a play session rather than a spec. The
complaint, in the player's own words, was that movement felt like *"Minecraft creative
mode"* where it wanted to feel like survival mode, with Satisfactory as the reference —
and that there was no jump at all.

**The deliverable is the tunability as much as the motion.** Twenty-two keys went into
`[player]` here and #30 added two more, and every one of them is expected to be wrong,
because nobody can pick a feel number without playing. Read the section comments in `content/tuning.toml` before changing
any of them; they say what raising each one does.

- **Jumping is Simulation state.** `_player_y` and `_player_velocity_y` in fixed-point
  metres, hashed, replaying. `player.jump_height_metres` is what is tuned and the impulse
  is *derived* from it with one `Fixed.sqrt` — a tuner thinks in how high they clear, and
  it means raising gravity makes a jump heavier rather than quietly making it too short to
  clear a Belt. **`JUMP` is held**, like `MOVE` and `FIRE`, and the *absence* of the intent
  is what re-arms it: `player.jump_repeats_while_held` is false, so holding the key through
  a landing does not bounce, and `_player_jump_armed` is the hashed fact that makes a jump
  a press.
- **Collision against the Factory arrived in #30**, the ticket #29 flagged when it shipped
  with the ground as the only solid thing. `_player_y` is still a height above layer 0 and
  nothing else, because building is still flat (DESIGN.md) — what changed is that the
  height of the ground under a player is now whatever the Factory put there. See "Standing
  on the Factory", below.
- **There are four accelerations, not one, and that is the central change.** Ground start
  (24 m/s²), ground stop (9), air start (6), air stop (1.5) — plus a fifth case, the
  landing settle, which takes `land_settle_acceleration_percent` of the ground figures away
  for `land_settle_seconds`. **A single figure for starting and stopping is the commonest
  cause of a first-person game feeling weightless**, because a body leans into a start and
  *slides* into a stop, and an instantaneous halt on key release is the loudest
  creative-mode tell there is. `_horizontal_acceleration` is the one function that decides
  which applies, from two facts: on the ground or not, asking to move or not.
- **The air-control decision is "nearer stiff", written as two small numbers rather than as
  a fraction.** Full air control feels floaty and arcade; none at all makes a jump
  unaimable. At 6 against the ground's 24 a jump commits you to roughly the trajectory you
  left on and gives you a quarter of the authority to argue with it, and the air
  deceleration of 1.5 means letting go in mid-air barely slows you — momentum is what a
  jump is made of. Set `air_acceleration_metres_per_second_squared = 0` for a ballistic
  jump.
- **Sprint is a gait, not a multiplier.** `_player_sprint_ticks` is one ramp, counted in
  ticks exactly as the Survey View lift is, and it drives the speed, the field of view and
  the bob *together* — which is what makes starting to run read as a change of gear.
- **Sprint is a toggle or a hold, and that choice is `game/player_controller.gd`'s.** The
  Simulation keeps knowing only whether a player *is* sprinting, which is the fact the
  movement code needs; `player.sprint_is_toggle` is read by the controller, which in toggle
  mode flips its own latch on the key's rising edge and sends the result. A replay
  reproduces either reading identically because what crossed the boundary is the intent and
  not the keypress. The latch is the same category of thing as the mouse buffer — a reading
  on its way in — and it is **cleared whenever the Simulation says the player is not on
  their feet**, so you respawn walking and the latch cannot drift from the flag.
  `sprint_is_toggle` is the one key in `tuning.toml` that is a *control preference* rather
  than a balance number; it is there because the project has no settings menu, and it is
  the key that moves out of content alongside `look_sensitivity_turns_per_1000_pixels` when
  one arrives.
- **The camera's response is in the Simulation and out of the aim**, which is the one
  genuinely arguable decision here and it went the way Survey View's transition already
  went. `_player_step_phase` is hashed state driven by **distance travelled rather than by a
  clock**, so a slow walk bobs slowly and a standing player does not bob at all; the
  landing dip hangs off `_player_landing_tick` and is scaled by the impact speed, so
  stepping off a kerb barely registers; the lean needs no state at all, because the
  sideways component of a velocity that is already hashed is exactly the quantity a body
  leans against. All five come out as their own `query_player_view_*` /
  `query_player_field_of_view_degrees` projections that **only the renderer reads** — folding
  a bob into `query_player_camera_height_metres` would mean a footfall moved where a round
  went and which tile the Build Gun was hovering. Contrast the recoil kick, which *is* in
  that query precisely because it does move the aim.
- **The jump is in the aim and the bob is not**, and that is the same split from the other
  side: how high a player is standing is a fact about the world, so `_player_y` is in
  `query_player_camera_height_metres` *and* in `_shot_target`'s eye height. A jumping player
  really is shooting down at the swarm.
- **The shipped camera values are deliberately barely perceptible**, on the player's own
  instruction — "only tiny minor bob please". 1.2 cm of vertical bob, 3.5 cm of landing dip,
  half a degree of roll at a walk: the kind of thing you notice when it is switched off
  rather than when it is on. Every one of them takes **0 as off**, which `Definitions`
  allows by name, because this is the easiest thing in the game to overdo into motion
  sickness and somebody prone to it is entitled to turn the lot off.

### Standing on the Factory

#30, and the ticket #29's own notes asked for. Before it a player collided with the ground
and nothing else: you walked through a Smelter and jumped through where its roof would be,
which made a Factory somewhere to stand *in* and never *on* — a diorama rather than a
building site.

**It is in the Simulation, in fixed point, and it could not have been Godot's physics.**
That engine is float-based, so a player's position would depend on a solver rather than on
the recorded inputs: two clients would part company on the first wall and every replay
fixture in the suite would quietly become a lie. What makes writing it by hand cheap is
that none of it is general 3D collision — everything is axis-aligned and grid-anchored, so
it is box tests against **one height per tile**.

- **`_solid_height` is a third field, not a column on the Enemies' two.** One entry per
  ground tile in fixed-point metres, 0 for bare ground, rebuilt by walking the structures
  under its own `_solid_height_stale` flag. An Enemy routes by flowfield and asks one
  question of a tile — may I walk through it; a player asks a different one — how high is
  it, because they can stand on the Machine an Enemy has to walk around. **A Belt is solid
  to a player and transparent to a Crawler**, and that difference is the point rather than
  an inconsistency: sharing `_flow_blocked` would have made it unexpressible and let each
  mechanic constrain the other for no reason beyond both being about geometry.
  `test_collision` asserts the divergence directly. Derived, so it is in
  `RunSave.DERIVED_PROPERTIES` and absent from `hash()`, like both flowfields.
- **Nothing overhangs, and that is what makes the whole mechanic cheap.** Every structure
  is a solid column from the ground to its height, so there is no ceiling to bump into,
  nothing to be trapped under, and "am I inside something" has exactly one answer: move
  up. A storey above layer 0 is the ticket that changes that.
- **What is solid.** Machines at the `height_metres` their row declares — the *housing*,
  1.5 m for a Smelter up to 2.4 m for a Press, with the Silo's 7 m launch tube deliberately
  not solid because a thin mast that stopped a player would read as a bug. Walls at
  `wall.height_metres`. Belts at `belt.deck_height_metres`. The Nest as two quantised
  terraces. A Node, a Breach and a Hive are deliberately **not** solid: the first two are
  ground rather than buildings, and walling a player out of a Hive would change the sortie.
- **`height_metres` is a column in `content/machines.csv`**, so a Machine's third dimension
  is a row like everything else about it, and `content/machine_bodies.csv` blanks it for
  every Machine that file declares — exactly the arrangement the footprint already had. The
  asset suite fails on a disagreement naming both files, because a mesh 70 cm taller than
  the declaration is a roof a player falls through. See
  [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md) section 6.

#### The Belt decision, and why it is a hop

**Belts are solid at their 0.9 m deck, and the decision is written as two inequalities**
rather than as a special case. The deck sits *above* `player.step_up_height_metres` (0.75 m)
and *below* `player.jump_height_metres` (1.1 m), so walking into a Belt line stops you and a
jump puts you on top of it to walk along. Both alternatives were worse: solid and unjumpable
makes a Factory a maze of knee-high fences, and a step-up makes a trestle something a player
stops noticing — a Belt is a real structure on legs, and the shipped tuning already assumed
a jump clears one (the comment on `player.gravity_metres_per_second_squared` says so in as
many words).

#### Climbing, and what the numbers add up to

A player reaches `jump_height_metres + step_up_height_metres` — 1.85 m — and that one sum is
the whole climbing system:

| From the ground you reach | And from a Belt deck (+0.9 m) |
|---|---|
| a Belt deck (0.9), a Smelter (1.5), the Nest's terrace (1.7), a Miner (1.8) | an Ammo Press (2.0), a Boiler or a Silo fort (2.2), a Press or a Repair Pylon (2.4) |

So **your own Factory is the staircase**, which is the factory-game answer and better than a
ladder nobody built. A Wall at 2.4 m is out of reach from the ground on purpose: it is the
one structure whose entire job is to stop something, so it has to stop a player too.

The Nest is a 4x4 ziggurat and a 4x4 footprint has exactly one ring and one middle, so its
three raked tiers of art quantise honestly to **two**: the terrace on the ring
(`nest.terrace_height_metres`, 1.7 m — within reach, which is the whole of what makes the
Nest climbable) and the crown in the middle (`nest.height_metres`, 4.2 m). The 2.5 m step
from one to the other is **not** reachable on foot, and that is deliberate rather than an
oversight: getting onto the crown wants a Belt or a Machine built against the Nest. Anything
finer would mean a collision grid finer than the build grid, which is a bigger change than
this mechanic is worth.

#### How a tick resolves, and what it costs

`_walk` brings `_solid_height` up to date once and then, per player: `_support_height` for
the floor under them (the tallest tile they overlap whose top is within their step-up), the
existing jump and gravity against *that* rather than against 0, then
`_move_against_the_factory`.

- **One axis at a time, x then z**, which is what makes walking into a wall at an angle
  slide along it rather than stop dead. The order is written down because it is the only
  thing here a player could notice, and two clients have to agree on it.
- **A refused axis keeps the coordinate it had rather than snapping to the obstacle's
  face.** Snapping is the usual choice and it is the wrong one here: the face is a tile
  boundary minus a radius, which still has to be re-tested for the two-wall corner, and
  getting it wrong puts a player *inside* a solid — the one state this must never produce.
  Refusing costs at most one tick of travel, 12 cm at a sprint, and it cannot be wrong.
- **Then the step up, once, after both axes.** A surface within `step_up_height_metres` of
  their feet is a surface they end up standing on: a kerb on the ground and a mantle in the
  air, which is one rule read twice rather than two mechanics.
- **"On the ground" became "on a surface"**, and `_is_on_their_feet` is the one place that
  is decided. Three things branch on it — the four accelerations, the stride and the bob —
  and all three used to ask whether `_player_y` was zero, which on a roof is the wrong
  question.
- **The cost is a handful of array reads per player per tick.** A player's box is 0.8 m
  across against a 2 m tile, so they overlap at most 2x2 tiles, and each of the three
  questions is a loop over those four. Repainting the field is
  O(Machines + Walls + Belt tiles) and happens only on a tick that built or lost something
  — never on a tick that merely moved somebody. A Factory of hundreds of Machines costs a
  walking player exactly what an empty Map does.

#### Getting stuck, and the one recovery

**A player's feet are never below the top of a tile they overlap.** That is the invariant,
it is restored on the tick it is broken, and `test_collision` pins it as an invariant rather
than as a list of cases.

The only way to be inside a solid is for the solid to have arrived — a Machine or a Wall
built on the tile somebody was standing on, which is an ordinary thing to do in co-op and an
easy thing to do to yourself while straddling a footprint edge. Movement cannot put a player
inside anything, because a move into something too tall is refused. So
`_lift_out_of_anything_built_on_them` puts them **on top of it**:

- **Up, never sideways.** Nothing overhangs, so the top is always free and up is the one
  direction guaranteed to resolve, where a sideways push has to pick a direction and can be
  refused by a second structure. And up is what reads correctly: the Machine went up
  underneath you, so you end up on its roof, which is also where whoever built it would want
  you.
- **A pocket of Walls is a roof, not a tomb.** Sealed in by Walls means standing on top of
  them, which is a way out — and a player who walls themselves into a corner still has a
  wrench and can demolish their way out of it.
- **Demolishing the thing you are standing on drops you**, with no special case anywhere:
  `_is_on_their_feet` compares against the support height, so the floor going away is a fall
  on the next tick.
- **A respawn is the one case the recovery is not allowed to discover.** `_respawn` has
  always put a player at the middle of the Nest's footprint, which was open ground until the
  Nest became solid — so it now puts their feet on the crown, deliberately. That is also the
  most interesting surface on the Map and the one thing nothing can build on and nothing can
  take away.
- **A Downed player collapses onto whatever is under them** rather than onto the ground: one
  who went down on a Smelter roof stays on the roof, for the same reason a corpse does not
  slide two metres.

**Open: a roof is not cover.** An Enemy's reach is compared horizontally — `_bite` subtracts
positions on two axes and has never heard of `_player_y` — so a Crawler on the ground can
still bite a player standing on a 2.2 m Boiler. That is the conservative default rather than
the considered one: the alternative is a free safe spot on top of every Machine in the
Factory, which would quietly undo the keystone loop, and the right fix is a deliberate
decision about how high is out of reach rather than an accident of which axes a subtraction
happens to use.

### Build mode is a hand, not a gate

**A Run opens with the weapon out** (#42, the player's own words: *"the knife being out
should be the default state"*). It used to open in build mode on the argument that the
first thing a Run asks of a player is a Factory; it asks for that second. What a player
does on the first tick is look at a world with things in it that can kill them. The Build
Gun is one keypress away and nothing is gated either way, so this is one line of initial
state — `_player_build_mode.fill(0)` — and not a restriction. What had to move with it is
worth knowing, because all of it is the same mistake in different places: `Objective.line`
now takes a player and prefixes the holster key onto a build step when the Build Gun is not
in hand; `test_recorded_session`'s fixture presses `B` before it builds anything, or every
click in it is a trigger pull; and every controller-driven build test grew a `_building()`
fixture that draws the gun first.

`B` holsters the Build Gun and draws the weapon, or the other way round. **Left click
places in build mode and fires in combat mode**, which is what #15's note said the real
answer was — it put the trigger on left mouse and shoved placing onto `E`, which its own
author called ugly. `E` is gone and `B`'s old job, laying a Belt, moved to `C`, where it
is only read with the Build Gun out, because routing a Belt is a build act. `C` collided
with #17's Silo charge counter, which moved to `K` — "Where the controls went" has the
whole map.

**And the Build Gun itself holds a tool**, Machine or Belt, which `C` swaps (#36). A Belt
has no row in `content/machines.csv` and cannot be one more position on the Machine list,
but a player laying one still has to be able to say so and have the mouse mean it: with
the Machine tool out a click places, and with the Belt tool out a press, a drag and a
release lay a route. `_player_build_tool` is Simulation state for the three reasons
`_player_build_mode` is, and **grep it and the only callers are its two queries,
`_apply_set_build_tool`, and `_apply_select_machine`** — which puts the Machine tool back,
because scrolling to a Smelter is a player saying they want to place one.
`test_nothing_in_the_simulation_asks_which_tool_is_out` pins that the way build mode is
pinned. `SET_BUILD_TOOL` carries the resulting tool rather than a flip, for the reason
`SET_BUILD_MODE` carries the resulting mode.

**It is not a mode in the gating sense, and the criterion is written as the absence of
code.** Grep `_player_build_mode` and the only callers are its three queries. Not one
refusal consults it, `_apply_build_machine` has never heard of it, and neither has
`_fight` — so a player holding a rifle builds exactly as well as one holding the Build Gun,
and `test_movement_weight` asserts that directly so nobody adds a flag. What the mode
decides is **which Input Action `game/player_controller.gd` produces from one button** and
which object `WorldView` draws in the player's hands. Switching is instant, unlimited, and
works mid-Wave, mid-burst and in Survey View.

- **The rule has one home, and #35 is why.** The first playtest reported the hologram *"still
  visible in gun mode"* and *"should not be placable in gun mode"*, and both came of the same
  shape: `_sync_hologram` asked `query_build_refusal`, which cannot know what is in a
  player's hands and must not, while `actions_for_tick` carried four separate inline
  `and in_build_mode` tests. Four checks on one side and none on the other is exactly the
  disagreement `query_build_refusal` exists to prevent, and it showed up as a green hologram
  over a click that did nothing. So the rule is now **`BuildGun.hand_refusal`**, returning
  `Refusal.BUILD_GUN_IS_HOLSTERED`, and `BuildGun.build_refusal` composes it with the
  Simulation's own. The hologram, the HUD panel and all four build acts go through that one
  function, and nothing else reads the mode to decide whether a build act happens.
- **It is the one `Refusal` nothing behind the façade returns**, and spelling it in the
  Simulation's enum anyway is deliberate: `Refusal` is the vocabulary `BuildGun.refusal_text`
  translates, and a second enum for one value would be two vocabularies for one HUD line.
  The *decision* never crosses the boundary — `build_refusal` lives in `game/`, no build path
  consults the mode, and `test_holding_a_rifle_does_not_stop_a_player_building` asserts from
  the other side that an intent that reaches `step` is applied whatever is in the hands.
  Holding a rifle does not stop a player building; it stops **this input** from placing.
- **The hologram is hidden rather than reddened, and only for this reason.** A red hologram
  says "not *there*" and invites a player to aim somewhere else; a holstered Build Gun is a
  fact about their hands and nowhere they aim will help. A promise nobody can keep is better
  not made than made in red.
- **`BuildGun.hand_refusal` takes the mode as an argument rather than reading it**, which is
  the one subtle part. The controller routes by the mode the player will be in once *this
  tick's* `B` has applied; the renderer draws the mode the Simulation is holding now. Those
  differ on exactly one tick of a swap and both are right, so the rule is a function of the
  mode and each caller supplies the one it means.
- **It is Simulation state anyway**, for three reasons that have nothing to do with
  permission: what somebody is holding is a fact about them in the same way their wallet
  is, a recorded replay has to reproduce a swap or every click after it means something
  different, and in co-op what the other three are holding is worth drawing.
- **`SET_BUILD_MODE` carries the resulting mode, not a flip.** A recorded script therefore
  describes what the player ended up holding without being replayed to find out, and two
  intents in one tick cannot cancel out. The controller reads the mode out of
  `query_player_is_in_build_mode` and sends the opposite — the arrangement the Machine wheel
  and the Gear slot ring already have.
- **Asking for the mode you are already in is a no-op whose hash does not move**, so
  leaning on the key does not restart the animation sixty times a second.
- **The mode flips on the tick the key is pressed and the model lags**, and **the lag is
  the renderer's, not the Simulation's.** #29 shipped `query_player_holster_blend` and
  `query_player_held_is_build_gun` before #28 landed, and they answer exactly the question
  `WeaponAnimator` answers from the clip lengths of the model on screen — so the renderer
  reads the mode and `WeaponViewmodel` plays the `holster`, swaps the model and plays the
  `draw`. The two queries stay here because `test_movement_weight.gd` pins them and they are
  the authoritative answer for anything that is not this renderer, but nothing in `game/`
  reads them. See "The weapon in frame", below.
- **`player.holster_seconds` is the budget for the swap you see, and until #35 it was read by
  nobody.** That is the third of the playtest's build-mode reports — *"swapping modes should
  be instant, not taking so long"* — and the player had already turned this key down and
  watched nothing happen, which was the bug rather than a misunderstanding. What they were
  waiting through was `WeaponAnimator.DEFAULT_SECONDS`: 0.3 s of `holster` plus 0.4 s of
  `draw`, seven tenths of a second on any clone without the purchased arms, timed off clip
  lengths the key has no part in. So `WeaponAnimator.Facts.swap_seconds` now carries it and
  each half of a swap is capped at half of it — **a ceiling, not a duration**, so the clips
  still decide the shape of a swap and a pack whose `PutAway` is already brisk is left alone.
  Shipped at **0.06**, three or four ticks, which reads as a cut with a hand in it. 0 is a
  hard cut. Split evenly rather than by the clips' relative lengths, because otherwise how
  long a swap takes would depend on which pack is installed.
- **The primary button is read both ways every tick.** `sample_devices` cannot know which
  mode anybody is in, so it samples the *edge* (one click is one Machine) and the *held
  state* (a trigger is not a click) and `actions_for_tick` picks. A player who presses `B`
  and clicks in the same tick gets the act of the mode they are swapping *to*, which is the
  rule that already makes a scroll-and-click place what the player scrolled to. #36 added
  a **third** reading of the same button, the *release*, which is the far end of a Belt
  drag — and the **number row** is read both ways on the same argument: with the Build Gun
  out `1`-`9` and `0` are the Machine picker, with the weapon out they are the weapon and
  Gear-slot keys they always were. `test_no_two_actions_share_a_key` therefore has an
  exemption with a reason written next to it, because deliberate sharing read by hand is
  exactly what that test must not forbid.

### Building you can see: ports, connection, the picker, the HUD and the one line

#36, and the player's own direction: *"building is very much NOT fleshed out, setting up a
basic production should be paramount"*. Every system underneath building worked; the act of
building did not. Five things changed beside the drag above, and **every one of them is a
query asked every frame rather than anything remembered** — the renderer holds no second
opinion about the Factory, which is the rule that makes all of this safe to add.

- **Ports are drawn.** An arrow on every declared port of every Machine standing and of the
  one the hologram is about to land, pointing the way goods travel, inputs cool and outputs
  warm. On the **dock tile** rather than the port tile: the port tile is part of the
  footprint, so a marker there is a marker inside the Machine — which a render showed
  immediately — and the tile outside is the more useful answer anyway, because it is where
  the Belt goes.
- **What is not connected is marked where it is not connected.** `query_belt_end_is_connected`
  and `query_belt_start_is_fed` are the geometry halves of `_hand_off` and `_load_from_port`,
  so a Belt drawn as connected is one that would really hand an Item over; a red post stands
  at every end that leads nowhere and an amber tag hangs over every Machine
  `query_machine_is_starved` calls starved. There is no stored connection to go stale, so
  demolishing the Smelter a Belt fed marks it on the next frame with no bookkeeping anywhere.
  An arrow a tile says which way each Belt carries.
- **The Machine picker is a row of cells**, one per Machine and one for the Belt tool, with
  the key printed on it, what it costs, whether a Delivery still has it locked, and the icon
  of **the Item the Machine makes** — which is what a player is hunting for when they go
  looking for a Smelter, and which means a Machine added as a row gets a picture without
  anybody drawing one. Those are #20's generated icons, which nothing had used. A Machine
  whose Recipe produces no Item — a Turret, a generator, a Silo — reads by its name, as does
  one whose Item has no icon yet (`iron_plate` is one): a missing picture is an ordinary
  state, the rule a Machine with no generated body already obeys.
- **The HUD is triaged.** It was fifty-three appended lines drawn over the Factory they
  describe. `hud_text()` is still the whole wall and the suite still asserts against it;
  what is *shown* is `hud_brief_text()` — the urgent banners, the objective, the Nest, the
  grid, what is in the player's hands, and the Machines in trouble by id and state. `H`
  shows the rest. The toggle is **not an Input Action**, for the reason saving is not: it
  does nothing to the Run and a replay has nothing to reproduce.
- **The three pictures are committed**, in `docs/images/building_placing.png`,
  `building_routing.png` and `building_running.png`, and
  `SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh` rebuilds them.
  They are the same claim as the contact sheets: the only honest way to judge what a player
  is told is to look at it.
- **One objective line, and it is not a tutorial.** `game/objective.gd` is a pure function
  of the Run's state — place a Miner on a Node, place a Smelter, drag a Belt between them,
  deliver — with nothing to enter, nothing to skip and nothing remembered. A player who
  builds the line before reading it never sees a word of it; one who demolishes their Miner
  an hour in gets the first line back, because the first thing is true again. It goes quiet
  for good once a Delivery tier has landed. It names roles and states rather than Machine
  ids, because a line that named `smelter_mk1` would be a second content table written in
  GDScript. It lives in `game/` for the reason `BuildGun.refusal_text` does.

### Refusals are a query, not state

A refused build stays a **silent no-op whose hash does not move** — a misaimed Build Gun is
an ordinary thing for a player to do. The *reason* is therefore a pure projection:
`query_build_refusal(player, machine, tile, rotation)` answers about a placement that has
not happened, and the hologram asks it every frame about the tile it is hovering over. The
reason is on screen **before** the click rather than after it, which is both better UX and
the only version that leaves the hash alone. `_apply_build_machine` consults the same
function, so what a player is told and what the Simulation does are one rule and not two.
The wording lives in `game/build_gun.gd`, because a `Refusal` is a fact and a sentence
about it is presentation.

### A Miner snaps onto a Node, and the snap belongs to the aim

#42, and the strongest thing in the second playtest: *"miners should snap to the nearest
node (within range) or show red"*. A Node is one tile and a Miner is four, so placing one
meant covering a flat marker on a textured floor with the corner of a footprint — which
makes the **first thing anybody builds the fiddliest thing in the game**, and makes its
failure mode silent: a Miner one tile off a Node is placed, paid for, and does nothing, for
ever, with nothing on screen saying why.

So with a Miner on the Build Gun, an aim within `BuildGun.MINER_SNAP_RANGE_TILES` of a Node
that Miner **could really work** puts the footprint on that Node, centred; an aim with no
such Node in range is red with words; and a Node whose Depth the Miner's `max_depth` does
not reach gets its own sentence, because the answer to that one is the next Miner up rather
than aiming somewhere else.

**The snap is the aim's job, not the Simulation's, and that is the decision in this
ticket.** The alternative — `_apply_build_machine` moves the tile in the intent before
placing — replays perfectly well, because the arithmetic is integer. What it does is make
the Simulation **silently relocate an intent**, which is the one thing this codebase has
refused everywhere else: `WRONG_SLOT` exists because a misfitted component is "refused
rather than redirected… silently moving it somewhere else would make a recorded script lie
about what happened", and `SET_BUILD_MODE` carries a resulting mode so a script "describes
what the player ended up holding without being replayed to find out". A `BUILD_MACHINE`
whose tile the Simulation moves breaks both sentences, and moves every Miner in every
fixture and every recorded session ever made.

Aiming, meanwhile, has always lived in `game/`, and `REACH_METRES` is the exact precedent:
a player pointing at the horizon gets a build at sixteen metres, not an `OUT_OF_REACH`
refusal, because `BuildGun.aimed_tile` decided where the gun was pointing before anything
crossed the boundary. `BuildGun.snap_to_a_node` decides the same thing with one more fact in
hand, so **what crosses is a tile, as it always was, and the replay is byte-identical by
construction** rather than by the snap being careful.

Three consequences worth holding on to:

- **The hologram and the placement are one call.** `PlayerController` and
  `WorldView._sync_hologram` both read `BuildGun.placement`, the same arrangement
  `query_build_refusal` has. The port markers and the HUD line read it too, because a
  hologram standing on the Node with its arrows at the crosshair is the same bug wearing a
  different hat.
- **The rule is not copied.** Whether a Miner's Recipe produces a Node's Resource, and
  whether its `max_depth` reaches that Depth, are two new queries —
  `query_node_yields_for` and `query_node_is_within_depth_of` — both one line over the
  private helpers `_machine_has_its_inputs` and `_miner_reaches` already use. Nothing in the
  Simulation reads them; they exist so that `game/` does not have to know the rule.
- **An aim with nowhere to put a Miner sends no intent at all**, exactly as an aim past
  `REACH_METRES` never sent a build at the horizon. The Simulation keeps no opinion about a
  Miner on bare rock — `_machine_has_its_inputs` still calls one starved, and a test or a
  co-op client can still place one — which is what keeps this a property of the Build Gun
  rather than a new gate.

Range is a constant in `game/` rather than a key in `content/tuning.toml`, for the reason
`REACH_METRES` is: the Simulation does not read it, and a tuning key the Simulation does not
read is a key `Definitions` warns about.

Not generalised past Miners. A Smelter dragged towards ore would be a Machine moving under a
player's aim for no reason, and nothing else in `content/machines.csv` has a tile it has to
be standing on.

### Materials

`content/machines.csv` has a `build_cost` column in the same `item:count` form a Recipe's
inputs use; empty means free. Building spends it out of the player's own stock and
demolishing returns it **in full**, along with whatever the Machine was holding and the
Items riding a demolished Belt. Nothing is destroyed, so demolish-and-rebuild is not a way
to make Items disappear, and iterating on a layout costs only the ticks it takes (issue #1,
user story 7).

**Destruction is the exact opposite and that asymmetry is the point** — see Mortality below.
A Machine an Enemy chewed down returns nothing at all.

Where the stock comes from is `player.starting_stock`: an explicit `item:count` bill rather
than the count-of-everything scaffold it replaced. It is granted once at construction, so
raising it mid-Run is not a way to conjure materials. The shipped value is
`"iron_plate:80"` — the whole competent Factory costs 78 — so **a Run opens with the opening
line and two plates over**, and everything past that is unlocked at the Nest.

A tuning key rather than a per-Item key, and a quoted string rather than a table, because
naming an Item in `sim/` is the one thing this project does not do: the set of Items is
whatever the Recipes mention, and a key called `starting_iron_plate` would be a second Item
table. It is parsed by the same `item:count` function a Recipe's inputs and a Machine's
`build_cost` go through, so there is one answer to what well-formed means.

**What refills a player's pockets is the Nest's store**, which is the symmetric half of the
opening bill and the thing that makes the Run a loop rather than a one-way spend. Build
materials used to go only outwards — into Machines, back only from a demolish or the
call-early bounty — so nothing the Factory produced could reach the Build Gun and a Run could
not fund a *second* Ammo Press out of its own output, which is exactly what the balance note
above says you need. See the Nest's store, below.

**Open: the store is not yet what arms a player.** #15 made firing spend **Ammunition** out
of these same pockets, and `player.starting_stock` is deliberately still plate alone — so a
Run opens able to build its line and swing a wrench and unable to fire a shot. The faucet
exists now; what has not been done is the pass that checks a Run can actually keep a magazine
full out of it, which is a balance question and wants somebody playing it. See the Gear
section.

### Rotation

`WorldGrid.rotated_footprint` swaps a footprint's extents without moving its anchor, so a
2x3 Machine turned a quarter covers 3x2 tiles from the same origin. One convention, shared
by placement validation and the renderer. Rotation is per-Machine state and is hashed; a
turned Machine covers different ground and presents its ports to different tiles.

## Delivery progression at the Nest

Where a Run gets better at anything. Progression is **physical**: goods carried or
Belt-fed to the Nest unlock the next tier of Machines, Gear components and Stratagems, and
there is no research menu and no science resource (GLOSSARY.md, DESIGN.md). That makes the
Nest both the thing you defend and the place you progress, so one location carries the
Run's whole meaning.

- **The tiers are `content/deliveries.csv`**, and adding one is a row. The table has
  **no numeric column at all**, which is how "unlocks are Machines, Gear components and
  Stratagems, never stat increases" is enforced: there is nowhere to write "+10% mining
  speed" even if somebody wanted to. `test_delivery` asserts the consequence directly —
  completing a tier leaves `query_definition_digest` exactly where it was, so no number the
  Run is playing by moved.
- **A Machine is locked because a tier names it.** There is no `locked` column in
  `content/machines.csv`: the Machines a Run opens with are exactly the ones no tier's
  `unlocks_machines` mentions. One authority, so moving a Machine between tiers is an edit
  to one file. The keystone loop is deliberately *not* behind the chain — a game that made a
  player earn the right to defend themselves before the first Wave would be a different
  game — so what the shipped chain sells is **Depth**: `t02_deep_mining` unlocks Miner Mk2
  and `t03_deep_survey`, which only a Mk2 working the Depth 2 seam can reach, unlocks Mk3.
  Each tier pays for the tool that opens the gate on the tier after it, and the deep seam is
  the one that opens new Breaches (#13) — so the chain is also what talks a player into being
  hunted from a second direction.
- **Locked content is a refusal, not a second gate.** `Refusal.CONTENT_IS_LOCKED` comes out
  of `_build_refusal`, before the ground and before the wallet, because being locked is a
  fact about the Machine rather than about the tile. A locked Machine may still be put on
  the Build Gun: the hologram asks that one function every frame, so the reason is on screen
  before the click — which is both better UX and the only version that leaves the hash
  alone.
- **The chain is walked in id order and nothing is skipped.** The next Delivery is the first
  tier this Run has not completed. A tier whose Depth the Factory has not reached *blocks*
  the chain rather than being passed over, which is the whole of "Depth gates what is
  possible to deliver". `Definitions` refuses a file whose `min_depth` goes backwards down
  the chain, because such a tier could never be the thing holding the chain up.
- **Depth is derived from the Factory, never stored.** `query_depth_reached` is the deepest
  Node a Miner is *actually working*, and it asks through `_miner_reaches` and
  `_recipe_yields` — the same predicates `_machine_has_its_inputs` asks — so the Delivery
  gate and the extraction rule cannot disagree about what a Factory is mining. A Miner Mk1
  parked on a Depth 3 Node is starved, and it has reached Depth nothing. The gate therefore
  measures something a player can argue with, and it falls again when that Miner comes down.
- **Goods reach the counter two ways and settle in one place.** A Belt whose far end points
  into the Nest's footprint hands Items to the open Delivery; a player standing within
  `nest.delivery_reach_metres` of that footprint hands over what they are carrying, clamped
  to the bill. Both go through `_accept_delivery`, and `_deliveries()` — one tick phase,
  straight after `_transport` — is the only thing that completes a tier. A tier that
  completed on one path and not the other would be two rules.
- **Goods past the bill are banked rather than refused, and nothing is destroyed.** The open
  tier takes what it is still waiting for and the Nest's store takes the rest, up to its cap;
  past that an Item is refused and the Belt **backs up where a player can see it**, exactly
  as it does against a full input buffer. `_nest_accepts` is the one way anything enters the
  Nest, and it pays the bill before the store — a store that swallowed ore the open tier was
  waiting on would quietly stall the chain a player is trying to finish. See the Nest's
  store, below.
- **Everything about the next Delivery is a query, and the HUD reads all of it.** Which
  tier, what it wants, how much has arrived, the Depth it is gated at, and
  `query_delivery_refusal` — a projection about a hand-over that has not happened, the same
  arrangement `query_build_refusal` and `query_call_wave_early_refusal` have. A player
  aiming a Factory at a goal they cannot read is guessing.
- **Unlock state is resolved ids, sorted, and hashed.** `_completed_delivery_ids`,
  `_unlocked_machine_ids`, `_unlocked_gear_ids`, `_unlocked_stratagem_ids` and the part-paid
  counter. Ids rather than indices for the reason `_machine_id` holds an id: a hot-reload
  that resorts the Delivery table, or inserts a tier ahead of the one already earned, must
  not renumber what a Run has earned. Sorted, so iteration order is a property of what was
  unlocked rather than of the order it was earned in. `RunSave` persists all five without
  being told, because it reflects over the Simulation's properties.
- **A fixture that is not about progression replaces the chain rather than walking it.**
  Several suites build the deeper Miners or fill a Factory out of a player's pockets, and
  neither the chain nor the opening bill is what they assert — so they substitute a tier that
  locks nothing and a stock that pays for anything (`DELIVERIES` / `STOCKED` in
  `test_depth`, `test_turrets`, `test_world_view`, `test_heat`, `test_enemies`,
  `test_nest`). `test_delivery.gd` is the one place the shipped chain itself is asserted.
- **All three unlock columns are read, and all three name a real row.** #15 made
  `_unlocked_gear_ids` the gate on what a player may fit to their weapon frame and #17 made
  `_unlocked_stratagem_ids` the gate on what a Silo may be loaded with, each through its own
  `Definitions.locks_*` — exactly the arrangement `unlocks_machines` already had, and the
  reason there is no `locked` column in `gear.csv` or `stratagems.csv` either. So the table has
  no identifiers in it that nothing reads, and the half that could not have been retrofitted —
  recording, hashing and saving what a Run has earned from the day it earns it — was already
  there when the mechanics arrived to consult it.

## Gear, first-person combat, and what dying costs

The other half of the keystone loop. #10 proved that production is combat power through a
Turret; this is the same claim in the player's own hands — **you fight with what your
Factory made** — and it is the project's highest-risk pillar, because code is the easy
half. First-person combat lives or dies on animation and feel, which no test can assert.
So the mechanism is built to be *tuned by playing*: every number that decides how a weapon
feels is a row in `content/gear.csv` or a key in `[gear]`, and editing either applies to the
Run you are standing in.

### One frame, interchangeable components, and no tiers

- **`content/gear.csv` is the whole of it, and nothing in `sim/` names a weapon, a
  component or a slot.** A fourth weapon is a row, exactly as a Cannon Turret was —
  `test_gear.gd` adds a Rivet Cannon to the shipped table and shoots a Breaker dead with
  it, with no code change at all.
- **The slot a component occupies is its own `kind`, and the set of slots is exactly the
  set of kinds the table mentions** other than the reserved `weapon`. That is the Items'
  arrangement — the set of Items is exactly what the Recipes mention, and there is no Item
  table — and it buys the same thing: a fourth slot is a row. The shipped table names four
  (barrel, magazine, sight, plating), interned in sorted order, and that order is hashed
  because it is the index space a `FIT_COMPONENT` intent travels in.
- **A weapon row carries no modifiers and a component row carries nothing else.** The
  loader refuses either mistake by name, which is how "power comes from combination rather
  than from tiers" survives contact with a designer: there is nowhere to write a Rifle Mk2
  even if somebody wanted to. A component whose six modifiers are all zero is refused too
  — a Delivery a player paid for and cannot feel is worse than no tier at all.
- **Modifiers are whole percentages, summed once and applied with one floor.** Additive
  rather than multiplicative so two components can be reasoned about in either order, so
  nothing rounds at each link, and so the order they were fitted in cannot reach the state
  hash. `_scaled` is the one function, and it works unchanged on a count of hit points and
  on a fixed-point count of metres.
- **A piece of Gear is locked because a Delivery tier names it**, exactly as a Machine is.
  There is no `locked` column in `gear.csv` and there will not be one: the Gear a Run opens
  with is exactly the Gear no tier mentions. So all three weapons are open from tick 0 — a
  game that made a player deliver goods before it let them hold a wrench would be a
  different game — and every component is earned, which is the pillar's whole point: **a
  build goal translates into a Factory goal.**
- **What a player is holding is an id, and what is fitted is a sorted array of ids.**
  Indices would renumber under a hot-reload; `_player_component_ids` is the same shape a
  player's pockets are, for the same two reasons.

### Firing, and where the aim comes from

- **No aim crosses the float boundary for a shot, and that is the strongest version of the
  rule rather than an omission.** `InputAction.Kind.FIRE` carries nothing at all. A
  player's yaw and pitch are already authoritative fixed-point Simulation state, put there
  by the quantised `LOOK` intent (#6), so where a round goes is something the Simulation
  knows exactly; a tile or a direction in the intent would be a *second* opinion about the
  aim, derived from a float, and in lockstep the second opinion is the one that diverges.
- **What did gain a crossing is the hand tool's aim**, and it went where every crossing
  goes: `InputQuantiser.aimed_tile_at_height`. `aimed_tile` is the Build Gun's and only
  ever meets the *ground*, because building is flat and a hologram snaps to a floor tile. A
  wrench is held against a Machine's body several metres up, so aiming it down the ground
  plane means looking at your own feet to mend something at eye level. Same three rules —
  floors toward negative infinity, bounded by reach, NAN reduced rather than cast — and its
  own tests in `test_input_quantiser.gd`.
- **`FIRE` is held, like `REPAIR` and `MOVE`.** Automatic fire is the absence of letting go
  rather than a second intent, and `_fight` consumes and clears the flag every tick, so it
  is zero at every point a hash is taken. One intent for all three weapons, because there
  is one frame: whether it swings or shoots is the `attack` column.
- **Combat resolution is integer arithmetic, all of it.** An Enemy is a point (#9), so a
  round is resolved against a capsule standing on it — `gear.enemy_hit_radius_metres`
  across, `gear.enemy_hit_height_metres` tall — with three tests in the order that rejects
  most cheaply: distance along the line of aim (a dot product), distance off it (a cross
  product), then the height the round is at by then (eye height plus the tangent of the
  pitch). The third is what makes aiming up and down mean something rather than firing a
  vertical plane of lead. Walked in Enemy index order on a **strict** improvement, so two
  Enemies exactly as far away hand the hit to the earlier spawn on every client — the rule
  a Turret's acquisition already obeys.
- **Two RNG draws every shot, hit or miss.** The stream is a function of how many times the
  trigger was pulled rather than of what happened to be standing there, which is what keeps
  a replay identical when a Crawler dies a tick earlier on one client than another. Melee
  consumes none: a swing catches the nearest living Enemy in front of the player inside the
  weapon's reach, because a swing is a sweep and not a ray.
- **A shot leaves from eye height, never from the camera.** Survey View lifts the camera to
  twenty-six metres and is explicitly not a mode, so a player who raises it to read their
  Factory must not thereby be firing from a helicopter.
- **Recoil is Simulation state because it moves where the next round goes.** A kick the
  renderer applied on its own would be a lie about aiming, and the pitch it adds to is
  authoritative already. `query_player_camera_pitch_turns` includes it, so the view and the
  aim are one number. The recovery is **proportional to what is left** — the one place in
  this project where that is the right shape, because recoil converges on *zero* and so has
  nowhere to drift, where Heat and the Power credit accumulate for forty hours and would. A
  flat recovery was tried first and is unusable: a weapon firing eight times a second adds
  eight kicks and a flat rate sheds two, so the view climbs without bound and a held trigger
  ends up pointed at the sky.
- **Firing spends Ammunition out of the player's own pockets** — the same pockets the Build
  Gun spends from. That is the first-person half of the keystone loop, and
  `query_fire_refusal` is the projection that lets the HUD read `DRY` off the weapon rather
  than off a count a player has to do themselves.

### Downed, dead, and back at the Nest

- **A player has health now**, which is what #11 said was missing: it could only read
  GLOSSARY.md's "a Breaker prefers Machines rather than players" as "rather than the Nest".
  `_enemy_contact_target` gained exactly one clause and nothing else — ranked **below a
  Machine**, so a Breaker with a Smelter in reach still chews the Smelter with somebody
  standing next to it, and **above the Nest**, so putting yourself in a doorway buys the
  Nest time at the only price this game charges: your own skin.
- **A player is reached by distance and not by tile contact**, unlike everything else an
  Enemy bites. The Nest, a Machine and a Wall stand on tiles; a player is a position in
  fixed-point metres, and asking which tile they are on would make a bite land or miss
  depending on which side of a boundary they happened to be, which is not something a
  player could read off the screen.
- **Solo play has no Downed state** (GLOSSARY.md), and that is the whole of the rule: there
  is nobody to revive you, so a Downed state on a one-player Run would be a pause with no
  counterplay. A solo player dies outright and waits out `player.respawn_delay_seconds`.
- **`_player_life_state` and `_player_life_since_tick` are the whole clock.** The tick a
  state began rather than a countdown, so how long somebody has been bleeding out is
  arithmetic over two numbers that are hashed anyway — no second counter to keep in step,
  and the "does not act on the tick it arrived" rule falls out for free: a player Downed
  this tick has been Downed for zero ticks. `_lives()` runs **last** in the tick, after
  `_enemies()`, because `_enemies` is what put them down.
- **Reviving is hand repair pointed at a person**, down to the arithmetic: an integer credit
  against the revive's own length, one floor applied to the total, and credit that does not
  survive letting go or walking out of reach. What it costs the rescuer is what a wrench
  costs — standing still, in the open, during a Wave, doing nothing else.
- **Death costs tempo and nothing else** (GLOSSARY.md, DESIGN.md), and the criterion is
  written as the *absence* of code: `_respawn` touches position, health and the clock. Not
  a plate, not a round, not a Delivery, not the components on the frame. There is nowhere
  in that function for a death penalty to be added without somebody arguing for it first.
- **Being Downed is a refusal, not a mode.** `_player_can_act` is consulted by every
  refusal a player's intent goes through, so `Refusal.PLAYER_IS_DOWN` comes out of the same
  function that does the refusing and the HUD gets the real reason. Nothing anywhere asks
  whether acting is *currently permitted* — it asks whether this player is on their feet,
  which is a fact about them in the same way their wallet is. Building is still never gated.

### Where the controls went, and the one that had to move

- **Left mouse places with the Build Gun out and fires with the weapon out.** #15 put the
  trigger here and moved placing to `E`, called that binding unhappy and temporary, and said
  the real answer was a hand — a holster that puts either the Build Gun or a weapon in front
  of the player. #29 built it: `B` is the holster, `E` is gone, and the Belt moved from `B`
  to `C`. See "Build mode is a hand, not a gate" in the player section.
- **Two keys moved when #29 and #17 met, and one of them was a bug being fixed.** #29 took
  `C` for the Belt and #17 had already taken it for the Silo's charge counter; the Belt
  stays, because `X` `C` `V` `B` — demolish, Belt, Wall, holster — is the build cluster and
  pulling a key out of the middle of it is the worse trade, so `KEY_SILO_CHARGES` moved to
  `K`, next to `KEY_LOAD_SILO` (`L`), which is the pairing that actually gets used: wind
  the count, then load. Separately, `T` was bound to **both** revive and withdraw from the
  moment #27 landed — press it next to a Downed teammate and you did both — and #29
  retiring `E` left the right key free: `KEY_WITHDRAW` is now `E`, beside `KEY_DELIVER`
  (`F`), which is the same act in the opposite direction.
- **The whole map, and no key appears twice *in one hand*.** `W` `A` `S` `D` walk, Shift
  sprints, Space jumps, `Q` is Survey View, `B` holsters, `C` swaps the Build Gun's tool
  between Machine and Belt, `V` Wall, `X` demolish, `R` wrench, `T` revive, `E` withdraw,
  `F` deliver, `G` calls the Wave, `Z` and `K` wind the Silo dial, `L` loads it, `P` paints,
  `H` shows the rest of the HUD, F5/F9 save and load. The **number row reads by hand**:
  `1`–`9` and `0` are the Machine picker with the Build Gun out, and `1`–`3` weapons and
  `4`–`7` component slots with the weapon out — the arrangement the primary button has had
  since #29, and the one thing `test_no_two_actions_share_a_key` cannot see, because the picker has no
  key constants of its own. `test_the_number_row_is_the_one_thing_two_acts_share_and_it_shares_by_hand`
  is the assertion that it does: in either hand, one press does exactly one thing.
- **Left mouse is three readings now**, not two: the edge places a Machine or anchors a Belt
  drag, the held state fires, and the release commits the route. Which it is, is the hand
  and the tool, decided in `actions_for_tick` and nowhere else.
- **Right mouse turns the hologram with the Machine tool out and flips the route's corner
  with the Belt tool out.** There is no hologram to turn then, and which way an L bends is
  the one thing about a route a player chooses — a tool deciding what the mouse means,
  which is the only kind of mode this project has.
- `KEY_JUMP` is **Space**, held.
- `KEY_1`–`KEY_3` are the weapon frames, in the sorted order the table interns them, so a
  fourth weapon becomes the fourth key without `player_controller.gd` changing. `KEY_4`
  onwards are the slots, each cycling the components that fit it with "nothing fitted" as
  one more position in the ring. The cycle holds no state: where it is comes out of
  `query_player_component` and what is in it comes out of the definition set.
- `KEY_REVIVE` (T) is held, like the wrench, and does nothing on a solo Run.

### The weapon in frame, and where it comes from

`game/weapon_viewmodel.gd` is the whole of it: the purchased first-person arms, their
weapon, and the clip that is playing on them, parented to the camera so the model and the
aim climb together. **Everything it moves by is read out of the Simulation** — the velocity,
the kick, the tick a shot fired on, the rounds left in the player's pockets — and the clip's
*time* is computed from the tick count and seeked explicitly rather than left to the
engine's clock, so what is on screen is a function of Simulation state and a replay looks
the same twice.

**The models are loaded at runtime from outside the repository, and are usually absent.**
The packs forbid redistribution and this repo is public, so a converted `.glb` is exactly as
forbidden as the FBX it came from (`docs/ASSETS.md`). `tools/assets/convert_weapons.sh`
writes one per weapon into a gitignored directory and `WeaponViewmodel` draws two
placeholder boxes for any weapon it does not find there. **A clone without the packs builds,
tests green and plays**, which is the rule, and `test_weapon_viewmodel.gd` asserts it rather
than trusting it. The conversion, and the four things about those FBX that bite, are
`docs/ASSET_PIPELINE.md` section 7.

- **`WeaponAnimator` is the state machine and it is a `RefCounted` with no nodes.** It takes
  a `Facts` — every field of which is a `query_*` — and returns a `Cue`: which role should be
  playing, how far into it, whether it loops, and **which weapon's model belongs on screen**.
  No assets, no scene tree, so every transition a player will ever see is a cheap assertion
  rather than something only a screenshot could catch. Clip lengths are *told* to it by
  whoever loaded the model, and anything it is not told falls back to `DEFAULT_SECONDS` — so
  absence of the packs changes what is **drawn** and not what **happens**.
- **A role is what the game asks for; a clip name is what a pack happens to call it.**
  `Shoot` against `Knife_Attack_1_Anim`, `PutAway` against `Holster`. `CLIP_NEEDLES` is the
  whole of the translation, resolved once when a model loads, and a weapon whose model lacks
  a take simply never plays that role — which is how the Bolt Rifle works a bolt and the
  Drum Autocannon does not.
- **A weapon change is two clips with a model swap between them**, and the holster belongs to
  the weapon *going away*. `Cue.weapon` lags `query_player_weapon` for exactly as long as the
  stow takes, because you cannot holster a rifle that has already been swapped for an
  autocannon. Neither clip can be fired through.
- **The bolt and the pump are only played by a weapon that has room for them.** A `Chamber`
  or `Pump` take runs after the shot clip and only when `query_player_weapon_interval_ticks`
  leaves time for both — otherwise the model would visibly cycle slower than the Simulation
  lets the player shoot. The Bolt Rifle's 48 ticks has room; the Autocannon's 7 does not.
- **A reload is not invented, because the Simulation has none.** A round leaves the player's
  pockets the tick the trigger goes, and the one moment that *is* a reload is the one a query
  can see: `query_player_shots_remaining` rising off zero — a player who was dry and now is
  not. A player who banks a second round while holding one has not reloaded, and a melee
  weapon has no magazine at all.
- **The trigger beats a reload outright**, which is what the Shotgun's
  `Reload_Start` / `reload` / `Reload_End` split is for: break out of the loop, shoot, and
  close the action afterwards rather than resuming it. A pack that ships one `reload` take
  plays one clip and the same code does both.
- **One model per weapon, built once.** A change hides one and shows another; the scene tree
  does not grow as a Run goes on, which is the rule every other thing in `WorldView` obeys.
- **The thing in a player's hands is an id, and nothing here knows it is a weapon.**
  `WeaponViewmodel.held_facts` and `show_held` are one struct and one call: change
  `Facts.weapon` to any id, hand it back, and the holster, the model swap and the draw
  happen by themselves — `draw` and `holster` are first-class roles here rather than a
  special case, because `Draw` and `PutAway` are first-class takes in the packs.
- **The Build Gun goes through that seam, and that is the whole of #29's holster in the
  renderer.** `WorldView._sync_weapon` reads `query_player_is_in_build_mode` and, when it is
  true, sets `Facts.weapon` to `BUILD_GUN_HELD_ID` with no reach and no magazine. Three
  lines. #29 landed before #28 and had built it as a second `Node3D` — its own meshes, its
  own sway, its own drop out of frame driven by `query_player_holster_blend` — and that is
  gone, because two answers to "what is in frame" is one too many. **The Simulation still
  owns which mode you are in**: `_player_build_mode` and `_player_mode_since_tick` are
  hashed, so a replay reproduces a swap and in co-op what the other three are holding is
  drawable. What it no longer owns is the *shape* of the swap, which `WeaponAnimator` was
  already timing off the clip lengths of the model actually on screen.
  `query_player_holster_blend` and `query_player_held_is_build_gun` stay in the Simulation —
  `test_movement_weight.gd` pins them, and they are the authoritative answer for anything
  that is not this renderer — but nothing in `game/` reads them any more.
- **A Build Gun model arrives the same way an arm does.** It is named `build_gun` in the
  gear directory, so the day somebody models one it loads, resolves its clips and draws
  without `world_view.gd` changing. Until then it is the same two placeholder boxes every
  unconverted weapon gets, sized stubby by a reach of zero — which is a real loss against
  what #29 shipped: its placeholder Build Gun had a flared nozzle and an emissive rail in
  the hologram's own colour, so the silhouette read as a tool rather than a gun at a glance,
  and that distinction is the point of a holster. **Modelling a Build Gun is the ticket that
  gets it back**, and it is art rather than code.

What is still placeholder-grade is the *surface*: the packs reference textures they do not
ship, so the arms and the weapons are repainted from `dieselpunk_palette.json` rather than
textured. Recovering the real maps is a nicer-looking ticket of its own.

### Where the balance stands

The Bolt Rifle kills a 30 hp Crawler in one shot and a 240 hp Breaker in six, one round a
shot, 0.8 s between them, 0.4° of scatter. The Drum Autocannon needs three shots for a
Crawler and twenty for a Breaker but puts out eight shots a second at two rounds each — so it
empties a magazine sixteen times faster for a little over twice the damage, and 5° of scatter
plus the recoil bloom means a long burst sprays where a tapped one does not. The Pneumatic
Wrench kills a Crawler in one swing at 0.6 s and cannot touch a Breaker before the Breaker
touches it.

A player has 150 hit points against a Crawler's 10 a bite and a Breaker's 60 — fifteen
seconds of standing in Chaff, three bites from the thing that actually hunts you, which is
the same sentence DESIGN.md writes about Machines. Hardened Plating takes 30% off that.

**The Ammunition chain closes, and `test_gear.gd` walks every link of it.**
`player.starting_stock` is deliberately still plate alone — putting rounds in it would conjure
exactly the thing the keystone loop says the Factory must make — so a Run opens with a rifle
that is a stick.
`test_a_player_can_take_the_ammunition_the_factory_made_and_fire_it` builds a Miner, a
Smelter and an Ammo Press out of the opening eighty plates, runs a Belt into the Nest, waits
for the counter to bank a round, withdraws it (#27) and kills a Crawler with it. That is the
pillar's whole sentence as one test.

**#26 measured the cost of shooting, and it is real.** `rifle_picket` is the `competent`
Factory with a second Belt banking Ammunition at the Nest and a player standing there with a
Bolt Rifle, drawing a magazine a minute and spending half of each minute on the trigger. It
**costs the Run 28 seconds** — 26m32s against 27m00s. The rifle spends rounds at 75 a
minute where the Ammo Press makes 37, so a player who
leans on the trigger is bidding against his own Turret for the same Press, exactly as the
Turrets section's arithmetic says he must. The honest reading stands: **a player who wants to
shoot needs a second production line**, and that is now a measured sentence rather than a
guess. `test_balance.test_the_rifle_at_the_nest_is_a_fourth_claimant_on_one_ammo_press` is
what keeps it true.

`gear.csv`, `[gear]`, `player.health` and `enemy.player_bite_reach_metres` were **not** moved
by #26. Nothing in the measurement contradicted them, and the Run-length lever that mattered
turned out to be `content/waves.csv` alone rather than anything a weapon does per shot. The two numbers still most likely to be wrong are
`gear.view_kick_degrees_per_shot` — the whole feel of automatic fire rides on it — and
`gear.enemy_hit_radius_metres`, which decides whether a swarm at twenty metres is a target or
a lottery. **Neither is measurable by a harness**: both are about what a fight feels like
through a mouse, and a scripted session has no opinion about that.

## The Siege Hulk, the Hives, and the sortie

The ticket that makes the first-person pillar justify itself. Everything else in this game is
solved by building; **a Siege Hulk cannot be**, and that is the whole reason it exists. If
killing one is not fun, that is the most important thing this project can learn, so the
mechanism is built to be *tuned by playing*: every number that decides how the fight feels is a
key in `[siege_hulk]` or `[hive]`, and editing either applies to the Run you are standing in.

### A boss is one more array entry

The claim ADR 0001's whole Enemy scale target rests on, tested again and held again. A Siege
Hulk is an entry in the same parallel arrays as a Crawler: a constant in `sim/enemy_kind.gd`, a
name in `KIND_NAMES`, a row in `content/waves.csv`, four `match` arms beside the Crawler's and
the Breaker's, and **one `if` in `_enemies`** that sends it to `_siege_hulk` instead of the
bite-and-walk path. No class, no second index space, no combat subsystem.

What it needed that no other kind does is **which way it is facing**, and that is *two more
parallel arrays* (`_enemy_face_x` / `_enemy_face_z`) rather than a class — the shape this file
has promised since #9. Held for every Enemy, including the ones it means nothing to, because a
parallel array is parallel.

- **A facing is a point, not an angle**, and that is the decision worth recording. An angle
  needs an arc-tangent, which fixed point does not have and which would mean a second table
  beside `Fixed.sin_turns`. A point reduces the weak-point test to **the sign of one dot
  product**: the hit came from behind exactly when the gap to the shooter points away from the
  gap to what the Hulk is facing. No normalisation, no rounding rule, no trigonometry, nothing
  for two clients to disagree about. `WorldView` turns it into a yaw with an `atan2`, which is
  `game/`'s business and a float it is allowed.
- **A Hive is deliberately *not* an Enemy entry.** It is a structure with hit points, so it is
  its own parallel arrays — the Enemy's half of the arrangement the Nest and the Walls already
  have on the players' side. Making it an Enemy was the other candidate and it is wrong twice
  over: it would put something that never moves through a movement loop and a flowfield on
  every tick of every Run, and it would make `query_enemy_count` — the number the HUD draws as
  "the swarm" and every Enemy test asserts on — permanently two higher on the shipped Map than
  the Wave that is actually arriving. A Hulk *is* an Enemy: it walks, it hunts and it dies. A
  Hive is furniture with hit points.

### Does it move? It arrives, holds, and backs off from Turrets

`_siege_hulk` is four clauses and the order is the design:

1. **A player at its feet is answered first, and a stomp spends the shell's cooldown.** One
   counter for both actions, so **a player standing there is a player whose Factory is not being
   shelled.** Closing the distance pays off from the first second rather than only at the end,
   which is the same trade standing in a doorway makes against a Crawler, at the same price.
2. **A Turret that could reach it makes it back off.** `_withdraw_enemy` is the only thing in
   the file that walks an Enemy *against* a field. This is "it cannot be defeated by Turrets
   alone" as behaviour: push a Turret line out and it withdraws and goes on shelling.
3. **Nothing in shelling reach means walk**, by the Crawlers' shared field — one more consumer
   of a field that is already built rather than a third sweep.
4. **Otherwise hold and bombard.**

So it is neither a chase nor a statue. A chase across a Map at 1 m/s would be tedium; a thing
that spawned already in position would have no legible arrival. It walks in, halts, and shells —
and `test_siege_hulk.gd` asserts it is still standing in the same place twenty seconds later.

**Where it halts is `siege_hulk.range_metres` and there is no second number.** It stops the
moment anything it can shell is inside its own reach, so the stand-off *is* the reach. And
`Definitions._check_siege_hulk_outranges_every_turret` refuses a content set in which any
Turret's `range_tiles` covers that distance — so **"it bombards from beyond Turret range" is a
property the content cannot be edited out of.** Adding a Cannon Turret that outranged the boss
is now an error naming the row rather than a quietly solvable boss. That check is why tuning is
read *last*, after `machines.csv`: it is exactly the cross-table question that ordering exists
for.

### A weak point, not a sponge

The decision this ticket turned on. **A damage sponge is a timer**: more hit points only ever
ask a player to hold the trigger for longer, and the answer to the boss would have been "bring
more Ammunition" rather than "move". So the front shrugs off `siege_hulk.frontal_armour_percent`
of a hit and the back does not, and a Hulk faces what it is shelling — which means flanking it
means going round **while it is busy with the Factory**. That is the decision this whole ticket
exists to put in front of a player, and it is made of movement rather than of inventory.

- `_armoured` is the one place it is applied, and **a Turret's round goes through it too**, from
  where the Turret stands. One rule, so a Hulk cannot be shrugging off a rifle and soaking an MG
  round in the same tick.
- A hit from exactly abreast counts as **behind**, generously and on purpose: the armour is the
  thing a player has to discover, and a boundary that punished a flank that was not quite far
  enough round would teach the wrong lesson.
- **Nothing tells the player where the weak point is.** The HUD says `ARMOURED FRONT 85%` and
  stops there; what carries the answer is the geometry — `WorldView` draws the hull in cast iron
  and an **unshaded glowing vent on the back**, offset along the Hulk's own facing. A player who
  empties half a magazine into the glacis and then walks round is the player that vent is for.
  This is the only place in the project where geometry carries a rule, and a HUD line naming the
  answer would spend the discovery.
- Per-kind hit volumes arrived with it: `_enemy_hit_radius` / `_enemy_hit_height`, because
  `gear.enemy_hit_*` is tuned for a low scuttling Crawler and a player who could miss four
  metres of armour by a metre would read the gun as broken.

### The bombardment, and why a shell is in the air

- **Targeting is deterministic and reads no unordered collection.** Machines in index order on a
  strict improvement in squared distance, then the Nest as one more candidate taken only on a
  strict improvement — so a Machine and the Nest at the same distance hand the shell to the
  Machine. The Factory is what a bombardment is for; the Nest is what is left when there is no
  Factory.
- **A shell takes `siege_hulk.shell_flight_seconds` to arrive, and that is the Telegraph rule
  rather than a flourish.** Nothing in this project may arrive unannounced (DESIGN.md), so the
  impact point is on the ground with a countdown for three seconds before anything happens
  there — long enough to walk out of six metres. `_shells()` runs *before* `_enemies()` so a
  shell fired this tick cannot land this tick, which is the same rule a Machine built this tick
  obeys.
- **A shell kills a player who stands in the marker**, at the same `shell_damage` it does a
  Smelter. That is deliberate: a telegraphed, avoidable, lethal thing is a mechanic, and death
  costs tempo and nothing else (GLOSSARY.md), so the punishment is affordable and the lesson is
  cheap.
- The blast is walked **from the highest index down** over Machines and Walls, because
  `_damage_machine` may destroy one and `_remove_machine` closes the gap. The damage is
  independent per target, so the direction cannot change the outcome — descending is what keeps
  the indices valid while it happens.
- `WorldView` draws the marker as a ring of ground scaled to `query_shell_blast_radius_metres`
  and brightening with `query_shell_ticks_remaining`, so **what a player dodges is literally
  where the damage will be** rather than an approximation of it.

### A Hive raises Heat; it does not open a second Breach

The other design question, and the answer is "raise Heat, not spawn", for a reason that is about
a promise rather than about cost. **GLOSSARY.md says Enemies enter at Breaches, which are "known
in advance and fortifiable".** A Hive that emitted its own Enemies would be a second entry point
nobody can fortify, and it would quietly take that promise back. So a Hive's pressure is routed
through the Breaches that already exist, by making the Factory louder than it is.

And it **subtracts from `heat.decay_per_minute` rather than adding to Heat**, which is the half
worth arguing about:

- Adding would hunt an idle Run for standing still, and DESIGN.md is explicit that Heat is
  throughput *in excess of what the Nest can hide* — a Factory producing nothing has nothing to
  hide and is owed its silence. `test_siege_hulk.gd` asserts exactly that: two minutes on a Map
  with a Hive and a Map without, both at Heat 0.
- Subtracting says the Nest hides **less** while these things are watching. So a Hive taxes
  *growth*: every craft counts for more while one stands, which is the same sentence pointed the
  right way.
- `_heat_decay_per_minute()` is the whole of the mechanic — one subtraction, derived every tick
  from the live set, nothing stored and nothing to adjust when a Hive dies. A Hive takes **no
  tick of its own**.
- And it lands on a gauge a player already reads. `query_heat_decay_per_minute` is on the HUD;
  killing a Hive moves it up, for ever, visibly. `query_hive_heat_shadow_per_minute` is the same
  fact stated as a bill, for the sortie panel.

**A destroyed Hive never comes back**, and that is structural rather than promised: nothing in
`sim/simulation.gd` appends to the Hive arrays after construction. Where they stand is geography
(`MapLayout`, sorted into canonical tile order like the Breaches); what is left of them is
Simulation state, because that is the half a Run changes.

**A Turret cannot touch a Hive, and that closes the obvious cheese by construction rather than
by a rule.** A Turret acquires *Enemies*; a Hive is a structure. So a player who runs a
fifty-tile Belt out to a Hive has built a Turret with nothing to shoot, and "requires leaving
the Factory" survives the most determined attempt to build its way out of it.

### What leaving costs, and making it visible first

The honest answer is that the cost is **diffuse**, and it is diffuse on purpose: this project
refuses to charge progress or resources for anything (GLOSSARY.md: death costs tempo, never
progress). What a sortie actually costs is the wrench you are not holding, the Machine you are
not rebuilding, the Wave clock that keeps running, and the shells that keep landing while you
walk. The work this ticket did was to make all of it **readable before the commitment** rather
than discovered on the way back — the arrangement every refusal in this file already has:

- `query_hive_heat_shadow_per_minute` — what the Hives are costing, per minute, right now.
- `query_player_metres_from_the_nest` — how far from a wrench you are, growing as you walk.
- `query_machines_damaged` — how much of the Factory is already hurt.
- plus `query_ticks_until_next_wave`, which was already there.

All four are projections the Simulation never reads back, so the panel cannot change the Run it
describes, and `test_the_bill_for_leaving_is_readable_before_the_player_commits` asserts the hash
does not move when it is asked. `WorldView._sortie_lines` puts them on screen the whole time
there is something out there worth leaving for.

**A visible bill is not the same as a felt cost.** #26 settled the *arithmetic* half of this —
the sortie measurably pays, five minutes of Run for two minutes away — but the question the
panel exists for is whether a player **hesitates** before walking out, and no harness has an
opinion about that. If they do not, the lever to reach for is `hive.heat_shadow_per_minute` and
`siege_hulk.shell_interval_seconds`, not a death penalty.

### Where the balance stands

- 1800 hit points against the Drum Autocannon's 96 damage a second is about **nineteen seconds
  of flanked, sustained fire** — and over two minutes through the frontal armour, which is the
  number that says "stop shooting it in the face" without a line of UI saying so. Roughly 270
  rounds out of the Factory either way, which is the pillar's whole point.
- The Bolt Rifle's 60 m reach is *exactly* the stand-off, deliberately: a player who will not
  leave the Nest **can** plink at it through its armour, for about five minutes of perfect fire.
  The sortie is strongly incentivised rather than enforced.
- 45 a stomp against a player's 150 is three stomps and a bit, and a 220-point shell kills
  outright.

**The Hives are measured now, and they are worth the walk.** `hive_sortie` is the `competent`
Factory plus one player who sprints about 104 m to the eastern Hive at two minutes in — east
along the Nest's latitude and then north-east, round the end of his own Factory, because #30
made the Smelter solid — takes it apart in fifteen seconds of wrench, and sprints back the same
way. Thirty of the Nest's 240 a minute of decay come
back permanently, and the Run goes from **27m00s to 29m36s** — two and a half minutes bought
with two minutes away from the Factory, which is a thinner margin than it sounds and exactly
the kind of claim that wanted measuring rather than asserting.
`test_balance.test_clearing_a_hive_lengthens_a_run` holds it.
`hive.heat_shadow_per_minute` stayed at 30, and so did `heat.decay_per_minute`.

**The Hulk's threshold moved, from 1200 Heat to 6400, and the reason is a hard finding.** At
1200 a Factory that was working reached it at about six minutes, and a Siege Hulk is
*unanswerable by a Factory by design* — DESIGN.md says it outranges Turrets, and 85% frontal
armour reduces an MG's 15 to 2, so 1800 hit points is 900 rounds fired from inside a 60 m
bombardment the 16 m Turret cannot reply to. A Run that met one at minute six was over at
minute eight with nothing a player could have built differently, which is precisely the
"unexplained spike" #26 was opened to remove — and it is why `fortified`, the only measured
scenario that defends its Machines, used to be the *shortest* Run in the table at 8m08s.

At **6400** the Hulk is gated behind a Heat only a Factory that kept its Machines alive *and*
its Turrets fed ever reaches. None of the eight measured scenarios gets there, and that is
deliberate as well as being the honest statement of where M1 stands: **the boss is the thing a
Factory earns by doing better than any of them.** The whole bet in one row — producing is what
summons the thing you are defending against — and the one row of the table a human still has
to fill in.

**What is still unplayed, and is the one thing a harness cannot play.** No measured scenario
answers a Hulk, because answering one means **flanking** it, and an open-loop scripted session
cannot walk a circle around something that is walking towards it. So `siege_hulk.*` is
untouched and the two numbers most likely to be wrong are still
`siege_hulk.shell_interval_seconds` — the whole rhythm of the fight rides on it — and
`siege_hulk.frontal_armour_percent`, which at 85% currently means the frontal arc is not
"expensive" but very nearly immune: a Bolt Rifle does 4 a shot into it, which is 450 shots.
Whether that reads as a discovery or as a broken gun is a question for a human with a mouse.

### Does the fight have a shape?

On paper, yes, and the shape is: *the shelling starts, you cannot answer it, you walk out, you
learn the front is wrong, you go round, and while you are round the back the Factory is quiet
because you are standing on its toes.* Three decisions in it that are not "hold the trigger" —
when to leave, which side to be on, and whether to melee it to buy the Nest time. That is more
shape than a sponge would have had.

What no test can tell us is whether the walk out there is dead time and whether the flank reads
as clever or as fiddly. Those are the two things to look for the first time somebody plays it.

## The Nest's store, and the faucet it is

Where Factory output becomes something a player can spend again. Progression put the Nest at
the centre of a Run; this is what makes it also the bank, so one location carries banking,
spending and the thing you defend.

- **A Belt into the Nest pays the open bill first and banks the rest.** `_nest_accepts` is
  the one way goods enter the Nest and `_nest_would_accept` is its pure twin, which is what
  lets `_hand_off_blocked` report a Belt backed up against a Nest with no bill and no room.
  Two paths into one function, for the reason `_accept_delivery` already was one: a surplus
  that banked off a Belt but not out of a hand would be two rules.
- **The store is capped, at `nest.store_capacity_per_item`, and that was the decision.** An
  unbounded store is simpler and it is wrong three times over. It is an infinite sink, so a
  Belt pointed at the Nest can always hand off and **never backs up** — and back-pressure is
  the one mechanism this game has for showing a player that a line is overproducing, at
  exactly the place they are looking. It removes any reason to stop hoarding and build the
  thing the materials are for, where a bounded one gives a late Factory's surplus somewhere to
  *go*. And it is a number in `hash()` and in the save file with no bound on it at all.
  Bounded, a full store refuses the hand-off and the Belt packs up, which is the rule a full
  input buffer already obeys rather than a new one — so "nothing is destroyed" keeps its teeth.
- **The store has room only for an Item a player could spend again, and that is what stops a
  Belt into the Nest starving the Factory that feeds it.** `Definitions.item_can_be_spent` is
  the question — an Item some Machine's `build_cost` names, or one a weapon fires — and
  `_nest_store_room` returns zero for anything else, so the cap above is a ceiling rather
  than the whole of the room. **Coal is the case this exists for.** Nothing is paid for in
  coal and no weapon fires it, so 200 banked coal was a Factory's own fuel converted into a
  number with no sink: #26 measured a Run that spent 98% of itself in Power deficit because a
  coal Belt a player had run to the Nest to pay `t01_munitions`' 20 coal went on diverting the
  Boiler's fuel for the rest of the Run, with the player having done nothing they could see.
  Now the bill takes its 20 and the store refuses the next lump, the Belt packs up where it
  can be seen, and **the diversion ends itself** — which is the back-pressure rule a full
  input buffer already obeys rather than a new concept. The *bill* still takes coal whenever a
  tier asks for it (`t03_deep_survey` wants 200), because a bill is paid before the store and
  a tier asking for coal is the Delivery chain making that diversion a visible, finite
  decision. **Deliberately not every Item a tier asks for**: banking against a tier that is
  not open yet is the store doing the chain's job, and it was the whole of the trap.
  `test_nest_store.gd`'s second acceptance test plays it on the shipped economy.
- **Per Item, not one pot.** One shared total would let a Belt of coal crowd plate out of the
  store: a cross-Item interaction nobody tuned, and one whose outcome depended on which Belt
  happened to arrive first. One number applied to each Item independently also names no Item
  in `content/tuning.toml`, which is the argument `player.starting_stock` makes for being a
  single quoted bill.
- **Separate arrays from the Delivery counter, not one pot either.** What is banked is
  spendable and what is on the counter is spent: `_delivery_items` clears when a tier
  completes and `_nest_store_items` does not, so a HUD reading "2/3" can never be a surplus.
  One pot would have to tell the two apart with a rule rather than with a field.
- **`WITHDRAW_FROM_NEST` carries an Item and a count, where `DELIVER_TO_NEST` carries
  nothing.** That asymmetry is deliberate: a hand-over has one open bill and one answer to
  what the Nest wants, so the only choice is *when* to walk over. A withdrawal has neither —
  the store holds several Items at once, and because nothing deposits by hand, a player forced
  to take all of one Item to get any of it could never put the rest back. The Item travels as
  an index into the sorted Item ids, for the reason a Machine does in `BUILD_MACHINE`, and the
  count is clamped to what is there exactly as a hand-over is clamped to the bill.
- **The refusal is a projection and the action consults it.** `query_withdraw_refusal(player,
  item_index)` answers about a withdrawal that has not happened — the arrangement
  `query_build_refusal` and `query_delivery_refusal` have — and `_apply_withdraw_from_nest`
  calls the same function, so what a player is told and what the Simulation does are one rule.
  It asks about the **Item and not an amount**: what a player hovering a store row wants to
  know is whether there is anything to take, and a count in the signature would make that
  answer depend on a number nobody has typed yet.
- **One reach, not two.** A withdrawal is made from `nest.delivery_reach_metres`, through the
  same `_player_is_at_the_nest`, so there is no spot a player can stand on where the Nest
  takes goods but hands none back.
- **A Nest that has fallen is not a counter.** `_nest_store_room` is zero once the Run is
  over, as `_delivery_would_take` already is, and a withdrawal is refused `RUN_IS_OVER`. What
  was banked stays banked, because nothing is destroyed; it simply cannot be reached.
- **Which amount the key asks for is presentation.** `PlayerController.KEY_WITHDRAW` sends one
  intent per Item the Machine on the Build Gun is still short of, for exactly the shortfall,
  because build costs are the only sink for materials in the game and so "what the thing I am
  holding still costs" is the amount a player wants every time. A counter with a row per Item
  would send the same intent with different numbers and the Simulation would not know the
  difference — the same split `BuildGun.refusal_text` makes.
- **`test_nest_store.gd` ends with the acceptance test, and it runs on the shipped economy.**
  `content/` unaltered: 80 plate, an opening line that costs 78, a second Ammo Press at 14.
  It stands the whole line up, checks that a second Press is `MISSING_MATERIALS`, lets the
  Smelter belt plate into the Nest, withdraws 14 and builds it. The Map is the test's own,
  because the starter Map's Nodes are far enough apart that joining them up is a lesson in
  Belt routing rather than a statement about materials — and it carries no Breach, so no Wave
  interrupts the accounting. What is being measured is whether the Factory can pay.


## The Silo, the Charges, the dial and the Painting

The design's most distinctive mechanic, borrowed from StarCraft's nuclear silo and sharpened,
and the clearest statement of the keystone loop there is: a Charge is assembled out of
Belt-fed plate and rounds, so **more production means more artillery, full stop** (DESIGN.md).

- **A Silo is a Machine whose output is a Charge rather than an Item**, which is the Turret's
  trick a third time. `role=silo` in `content/machines.csv`, a Recipe with inputs and no
  outputs, and `_craft` advances it exactly as it advances a Smelter. The only thing the
  Simulation adds is what happens instead of depositing an output: `_assemble_a_charge`.
  **`produces_no_items()` is the predicate it joined** rather than a rival — a generator makes
  Power, a Turret makes damage or repair, a Silo makes a Charge, and the loader's
  outputs-must-be-empty rule needed no new clause. There is no Silo table: the stockpile, the
  loaded shell and the loaded count are three more per-Machine arrays indexed exactly like
  `_machine_progress_ticks`, because giving a Silo its own index space is how a Silo stops
  being a Machine.
- **A full Silo is idle and off the Power grid**, by one more clause in `_machine_would_work` —
  the single predicate behind what the grid bills, what advances and what a query calls
  starved. Deliberately *not* starvation: it has everything its Recipe asks for and nowhere to
  put the result, which is exactly the standing a Turret with nothing in reach has. Without it
  a Silo at capacity would go on eating plate and rounds and browning out the Factory to
  produce nothing.
- **`charge_capacity` is a column, so a bigger Silo is a row** — the argument `range_tiles` and
  `damage` already made. How much artillery a Factory can bank is the most consequential number
  about a Silo and it belongs next to the Power it draws and the hit points a Breaker has to
  chew through to take the stockpile with it.
- **A destroyed Silo loses its stockpile, and so does a demolished one.** `_remove_machine`
  drops the three entries and nothing anywhere hands a Charge back — #11's asymmetry applied to
  the most expensive thing a Factory can be holding, plus the one extra claim this mechanic
  makes: a load is irreversible, so taking the Silo apart must not be a way to undo one. A
  Charge is not an Item, so there is nothing for `_refund_machine` to return even if it wanted
  to. That is what makes a breakthrough threaten the players' heaviest weapon and not just
  their smelters.

### Loading by hand, and why it cannot be taken back

DESIGN.md names Silo loading **first** in its list of diegetic controls, and the reason is in
the same paragraph: friction is satisfying when it is problem-solving under pressure and tedious
when it is transcription. An irreversible commitment made *before* the fight is the first kind.

- **The dial is per-player Simulation state and commits nothing.** `_player_dial_stratagem` and
  `_player_dial_charges` are where a player has wound the shell selector and the charge counter
  before they walk over — the arrangement `_player_selected_machine` has, for both of its
  reasons: the controller may hold nothing authoritative, and in co-op what somebody else is
  winding up is worth drawing. Per player rather than per Silo, because a shared dial would let
  one player change another's commitment under their hands.
- **`LOAD_SILO` is the irreversible one, and the irreversibility is the absence of code.**
  There is no unload intent and there will not be one; `_load_silo_refusal` returns
  `SILO_ALREADY_LOADED` rather than replacing what is in the tube; and the only thing that ever
  clears a load is a Painting beginning. Fire what you loaded or lose it with the Silo.
- **A Charge is a multiplier, not a second Stratagem.** The count on the dial scales whichever
  magnitude the row quotes — `damage_per_charge` for a Barrage, `goods_per_charge` for a Supply
  Drop or a Sentry's magazine — so four Charges mean the same thing whatever is in the tube, and
  there is one rule rather than three. `silo.max_charges_per_load` is the dial's upper stop and
  is deliberately a *different* number from a Silo's `charge_capacity`: one says how much
  artillery a Factory may bank, the other how big one strike may be.
- **The refusal is a projection and the action consults it**, which matters more here than
  anywhere else in the project because this is the one act a player cannot take back. The HUD
  reads `query_load_silo_refusal` every frame about the Silo the key would commit to, so "already
  loaded — fire it or lose it" is on screen *before* the key goes down. That is what makes the
  irreversibility fair rather than cruel.
- **Which Silo the key means is presentation, and `game/` owns it.**
  `PlayerController.silo_tile_for_loading` is the Silo under the tool aim, or failing that the
  first Silo in reach, and **the HUD calls the same function** — a reason on screen about a
  different Silo from the one the key means is worse than no reason at all. Reach itself is the
  Simulation's answer, asked through the refusal, so there is no second opinion about how far an
  arm goes. The same split `BuildGun.refusal_text` and `KEY_WITHDRAW`'s choice of amount make.

### Painting, and what an interrupted one costs

The best co-op moment the design has, because one player is committed and helpless while the
others cover them (GLOSSARY.md).

- **The Charges leave the Silo on the tick the channel begins.** That is the whole of "an
  interrupted Painting consumes the Charge and produces nothing" — it is true by construction
  rather than by a rule somebody has to remember, because `_begin_painting` takes them out and
  there is no path by which they go back. Every interruption is then simply the channel not
  finishing.
- **Three things interrupt it: letting go, aiming somewhere else, and being hit.** `PAINT` is
  held and sent every tick, like `REPAIR` and `FIRE`, so releasing it *is* the interruption; and
  `_damage_player` calls `_interrupt_painting` on **any** damage rather than on going down,
  because a Stratagem a player could soak two Breaker bites through would not be exposed in any
  sense a player could feel. That one clause is what makes covering somebody a job.
- **A player must stand at the target, literally.** The painted tile is the tile under their
  feet — `_paint_refusal` returns `NOT_AT_THE_TARGET` otherwise — rather than a tile within some
  reach, because the whole price of a Stratagem is walking into the place you want it to land.
  It is also why `_walk` roots them once the channel starts: "at the target" has to mean
  something. **No aim crosses the float boundary**, for the reason `FIRE` carries none: where a
  player stands is authoritative fixed-point state already, so the controller derives the tile
  from a query.
- **Being mid-Painting is a refusal, not a mode.** `_act_refusal` is the one function every
  refusal a player's intent goes through now opens with, and it answers `PLAYER_IS_DOWN` or
  `PLAYER_IS_PAINTING` — two states in which a player does nothing, both *facts about them* in
  the same way their wallet is. Nothing anywhere asks whether acting is currently permitted, and
  building is still never gated. It is deliberately **not** folded into `_player_can_act`, which
  `_damage_player` and `query_player_is_alive` consult: a player mid-Painting is emphatically
  still alive and still takes the bite that interrupts them.
- **What interruption cost is state, not an inference.**
  `_player_paint_interrupted_tick` and `_player_charges_wasted` are hashed and saved, for two
  reasons. A player has to be able to read what a lost Painting cost them — a Charge that
  vanished with no accounting is exactly the bad luck Heat is built to avoid. And it is what
  lets a replay fixture *prove* an interruption happened rather than infer it from an effect
  that failed to arrive, which is a weaker claim about a stronger-sounding thing.

### The three Stratagems, and what each one reuses

`content/stratagems.csv` is the whole of it and **nothing in `sim/` names a Stratagem**. What
the Simulation knows is the three `effect` values; a second Barrage with a wider radius and a
longer channel is a row.

- **Artillery Barrage** takes `damage_per_charge × charges` off every Enemy within
  `radius_tiles` of the painted tile. Reach is compared **squared**, like a Turret's and a
  wrench's. Walked in **descending** Enemy index order — the one place in the project that does
  not walk Enemies forwards — because nothing here is a *choice* between Enemies, so there is no
  selection bias to avoid, and a kill removes its entry immediately exactly as `_fire` does.
  Enemies only: there is no friendly fire anywhere in this Simulation and this would be the one
  place it existed.
- **Supply Drop** hands `goods_per_charge × charges` to the painting player through
  `_give_to_player` — **their own pockets**, which are the same pockets the Build Gun spends
  from and a weapon fires out of. That is what makes it the answer to having run out; a drop
  that banked at the Nest would be a Delivery run in reverse and would ask the player to walk
  home, which is what a Stratagem is for not doing.
- **Sentry Drop** calls `_place_machine` with the Turret its row names, an expiry tick, and its
  input buffer pre-filled. **It is an ordinary Machine in every respect a player can observe** —
  it aims through `_aim`, spends rounds through `_craft`, obstructs Enemies, can be chewed down,
  and does not work on the tick it arrived. The two things that make it a Sentry are that expiry
  tick and that pre-filled buffer, and neither is a mechanism: it is how a Machine that arrived
  from outside the Map and needs no Belt is expressed in arrays that already existed.
  `_add_to_input` is uncapped — the cap lives in `_input_has_room` and belongs to a *Belt*
  hand-off — so a Sentry legitimately arrives holding more than a Belt could ever have put
  there, which is the literal content of "needs no Belt", and
  `query_turret_ammunition_capacity` reports `max(capacity, held)` so the gauge tells the truth
  about it.
- **`_place_machine` was extracted for this**, and it is the one place a Machine joins the
  Factory. A Sentry Drop places a Turret with no Build Gun, no build cost and nobody standing
  there, and a second copy of those appends would have been a second place to forget an array.
- **`_expire` walks Machines in descending index order** so removing one does not skip the next,
  and runs before anything reads a Machine index for the tick — the grid, the aim, the craft — so
  a Sentry whose time ran out draws no Power and fires nothing on the tick it goes. Its rounds
  go with it, for a different reason from a destruction: they were never the Factory's, so
  letting a Sentry expire next to a Belt is not a way to bank a Supply Drop.
- **Which Silo a Painting draws from is geography.** `_loaded_silo` takes the loaded Silo whose
  tile comes first in canonical tile order, through `MapLayout.tile_precedes` — the single
  definition of tile order this project has. Index order would have made "which of my two Silos
  fired" a fact about which one a player happened to build first.

### Where the balance stands

A Barrage Charge is 150 points against a Crawler's 30 and a Breaker's 240, over a six-tile
radius, behind a five-second channel — so one Charge clears Chaff and two kill a Breaker, if a
player can stand still for five seconds in the middle of it. The Silo's Recipe is **a plate and
twenty rounds every twenty seconds**, deliberately priced in the very Item a Turret and a
player both spend: artillery competes with the magazine rather than being free once the line is
up. `silo.max_charges_per_load` is 4 against a capacity of 8, so a full Silo is two strikes
rather than one big button.

**#26 could not measure the Silo and recorded why as a finding; #37 measured it, and what the
finding turned out to be was arithmetic.** A Silo draws 400 kW and the opening Factory draws
**660** of the 900 one Steam Boiler and the Nest's baseline plant supply between them, so a
Silo beside it asks for 1,060. The step that does not follow is the next one: the shipped Map
has one coal Node yielding 40 coal a minute against the 30 a Boiler burns, which #26 read as
"there is no second Boiler to be had". A Boiler is on the grid only *while it is burning*, so
40 coal a minute is **1.33 Boilers burning** rather than one Boiler burning and 10 coal a
minute piling up on a Belt — two Boilers on one Node are worth about 800 kW of average supply
instead of 600, and 300 + 800 pays for the Silo. See "The one Power grid".

So **a Milestone 1 Run can power a Silo, and the Silo is something it builds toward.** The
`artillery` row of the balance harness is the Run: a second Boiler on the same coal Node, a
second Miner and Smelter on the spare iron Node — because the Ammo Press can use every plate
the first Smelter makes, so the Silo's plate is better *made* than branched off it —
ninety-six plate found seven pulls of the call-early lever at a time, and then a walk, a dial,
an irreversible load and five seconds of standing still. It fires a **Sentry Drop**, which is
the one Stratagem the shipped chain does not lock. Measured with #46 in, the Run is **15m22s**
against `competent`'s 28m48s — 47% shorter — with 36% of it in Power deficit, 7 Charges banked
at the peak against a capacity of 8, and 32 rounds still in the Factory at the end.
**Nothing in `content/` changed to make any of that true.**

Two things that measurement settles and one it sharpens. The twenty-rounds-a-Charge figure is
**not** the number most likely to be wrong: the Silo is a third claimant on the Press and since
#46 it takes an equal share of what the Press makes rather than the overflow off a sixty-round
Belt — which is 48 seconds of Run and still a Charge every forty seconds, comfortably. What
costs the Run is the 400 kW and the seven lever pulls, not the rounds. And the plate is the real
bottleneck, which no amount of tuning the Recipe would have shown.

`paint_seconds` is still unmeasured — five seconds is a guess at how long a player can be asked
to be helpless, and it is the whole feel of the mechanic. `artillery` fires a three-second
Sentry Drop rather than the five-second Barrage, because `artillery_barrage` is locked behind
`t03_deep_survey` and a Run that has paid for that is a different measurement.

## The joint balance pass

Every system in this game was priced in isolation, and #26 is where they were first measured
together. Before it, the recorded Run lengths came from #9's scaffold schedule, which grew a
Wave's count but never its arrival rate; #12 replaced that with Heat, #13 added Depth
surcharges, #16 added two Hives taxing the decay and #17 added a fourth claimant on the one
Ammo Press. The figures were stale in the strong sense: not merely old, but derived from a game
that no longer existed.

**The method is a measurement and not an argument.** `tools/balance/measure.sh` plays scripted
sessions headless to the end of the Run and reports what happened. Change a number in
`content/`, run it, read the table. Three files:

- `tests/balance_scenario.gd` — a scenario is a function from tick number to Input Actions and
  nothing else, so it replays. `to_script` hands it to `DeterminismHarness` unchanged, and
  `test_balance.test_a_scenario_is_a_replayable_input_script` proves two minutes of one
  tick-for-tick.
- `tests/balance_probe.gd` — plays one scenario on one seed and reports the tick the Nest fell,
  which Wave was on the Map, how long the Factory held no Ammunition, which Machines went
  missing, what the Power grid was doing, and a sample a game minute throughout. It reads the
  Simulation only through `query_*` and issues nothing but Input Actions, so a measurement is a
  session the game could have had. **It records facts and derives the cause from them**, with
  every threshold a named constant at the top of the file.
- `tests/balance_scenarios.gd` — the eight sessions of record, on `MapLayout.starter()` with
  `content/` off disk and `player.starting_stock` as written. Every one past `bare` contains
  the same six Machines on the same tiles, so the difference between two rows is the difference
  between two *decisions*.

`tests/cases/test_balance.gd` asserts the shape in bands rather than ticks — the exact figures
belong here, and a test that pinned the tick would turn every legitimate tuning change into a
red suite. It costs the suite about two minutes, which is why it caches a played Run and reads
it from several methods.

### The table, measured 2026-10-08

Seeds 7, 11 and 29, and **every scenario ends on the same tick on all three.** `rifle_picket`,
the one row that has ever spread, now differs only in peak Heat — 6186, 6178, 6174 — and not in
when it ends. See "What the seed can reach", below.

**Every column is the same scenarios through the same harness.** The first two differ by four
numbers in one content file and nothing else. The third adds #30's collision and #34's Breaker
approach. The fourth adds #37's two rules and the ninth scenario they made measurable, and moved
not one of the eight rows of record. The fifth adds #35's separate
`heat.first_wave_interval_seconds`, and it is **one fresh run of `tools/balance/measure.sh` on
the merged tree** — because #34, #37 and #35 each re-measured on their own branch, the schedule's
two ends belong to different tickets, and hand-merging three tables would record figures no Run
ever produced. See "What collision cost the two sorties", "What #34 cost the table", "What #37
cost the table" and "What the shorter first Wave cost", below. The sixth is #46's branching
Belts, measured on the merged tree with all nine scenarios unchanged, so the delta is attributable
to the mechanic alone — see "What #46 cost the table".

| Scenario | #26 before | #26 after | #34 | #37 | merged | **#46** | Wave | Peak Heat | What killed it, now |
|---|---|---|---|---|---|---|---|---|---|
| `bare` — builds nothing | 4m22s | 4m22s | 4m22s | 4m22s | 3m22s | **3m22s** | 1 | 0 | undefended: the first Wave alone |
| `opening_line` — the line, no Turret | 3m39s | 4m04s | 4m04s | 4m04s | 3m12s | **3m12s** | 1 | 615 | undefended, and *sooner than `bare`* |
| `competent` — six Machines, one MG on the lane | 17m45s | 27m00s | 29m07s | 29m07s | 28m48s | **28m48s** | 35 | 6725 | **a Siege Hulk standing**, 96 rounds still in it |
| `over_producer` — the same plus an unbelted Miner | 10m30s | 19m36s | 20m21s | 20m21s | 20m21s | **20m21s** | 25 | 6841 | the same, **29% sooner** than `competent` |
| `fortified` — a second MG over the Factory | 8m08s | 29m15s | 28m45s | 28m45s | 28m45s | **28m45s** | 35 | 6716 | the same, 112 rounds unspent — **a wash** |
| `deep_digger` — pays the chain, digs Depth 2 | 8m13s | 10m48s | 10m48s | 10m48s | 10m48s | **11m03s** | 12 | 2995 | swarmed, 16 rounds left, with **two Breaches** open |
| `hive_sortie` — clears the eastern Hive | 19m13s | 29m36s | 32m22s | 32m22s | 32m05s | **32m05s** | 39 | 6672 | the same, 3m17s *later* — the longest Run measured |
| `rifle_picket` — a rifleman on the same Press | 8m04s | 26m32s | 27m16s | 27m16s | 28m02s | **28m02s** | 34 | 6186 | swarmed, 46s sooner than `competent` |
| `artillery` — grows a Silo and fires it | — | — | — | 16m10s | 16m10s | **15m22s** | 20 | 4906 | swarmed, **47% sooner** than `competent` |

**#36 moved no row of this table, and that was the control its shape predicted**: it gave a
player a Belt-routing tool and a port table to aim it with, and a scenario issues `BUILD_BELT`
directly rather than dragging a mouse.

`rifle_picket`'s **27m16s** in the #34 column corrects a transcription error — 27m13s is the
figure on seeds 11 and 29, and seed 7, which the table quotes throughout, printed 27m16s.
Corrected openly rather than quietly, because the whole value of this table is that somebody can
re-derive it.

**Which ticket owns which row.** The last column is legible once you know that a Run has two ends
and different tickets own them. #35 shortened the *first* Wave interval, so it moves the rows that
end during the first Wave and nothing else: `bare` and `opening_line` lose a minute each, and they
are the only rows where #35's own branch figures survive the merge intact. #34 changed the *late*
tiers, so it moves the rows that reach them — every long Run now ends with a Siege Hulk standing
rather than having run dry. #37 made a Silo powerable, which did not move a row but added the row
a Silo was always missing. And the three rows that end in between — `over_producer`, `fortified`,
`deep_digger` — are **bit-identical across the last three columns**, because a Factory that dies
at minute twenty never notices where the first Wave started.

`competent` is the one row #34 and #35 both touch: 28m48s, nineteen seconds short of #34's
29m07s, which is what #35's earlier first Wave costs it and no more.


**The loop the spec asks for lands.** Build nothing and lose in three minutes. Build the opening
Factory and get twenty-eight, lost to a boss with a name and an answer. Walk out and clear a Hive
and get thirty-two, the best Run measured. Spend the lever's plate on a Miner nothing collects
and lose a third of it. Dig to Depth 2 early and lose two thirds. Stand at the Nest spending the
Turret's own rounds and lose forty-six seconds.

What the *before* column says on its own is the thing #26 was opened about: **the better a
Factory was, the shorter its Run.** `fortified` — the only scenario that actually defends its
Machines — managed 8m08s, against 17m45s for the Factory that built no second Turret at all
and 10m30s for the one that spent the same plate on a Miner nothing collects. Keeping the
Factory alive kept its Heat climbing, and a Siege Hulk arrived at minute six that nothing it
owned could shoot. A balance in which competence is punished is not a difficulty problem, it
is an inverted gradient, and no amount of playing would have taught a player anything from
it — which is the case for measuring before tuning rather than after.

### What was changed, and why

Four numbers, all in `content/waves.csv`, which is less than a tuning ticket is allowed to
cost. The file carries the reasoning inline; the short version:

| Row and column | From | To | Why |
|---|---|---|---|
| `chaff_crawlers.heat_per_extra` | 150 | **1200** | At 150 a Factory earned itself two extra Crawlers on its very *first* Wave, and the Chaff tier alone outgrew one Ammo Press by minute five — so every Run was eighteen minutes long whatever a player did. At 1200 the tier is a slope: 6 Crawlers at minute three, 10 at minute twenty-five, and the stockpile banked in the quiet minutes is what carries the middle of the Run. |
| `shock_breakers.min_heat` | 500 | **5200** | 500 was reached at two and a half minutes, before a player can afford a second Turret, and the Breakers took all five production Machines from minute three. #11 flagged this threshold as the one most likely wrong; it was. 5200 is about minute twenty-six. |
| `shock_breakers.heat_per_extra` | 900 | **1800** | Set against the new threshold so a second Breaker is a later Wave rather than the next one. |
| `siege_hulks.min_heat` | 1200 | **6400** | 1200 arrived at six minutes, and a Siege Hulk is unanswerable by a Factory *by design* (DESIGN.md: it outranges Turrets). 6400 is reachable only by a Factory that kept its Machines alive and its Turrets fed, which makes the boss the thing that arrives because you were doing well. |

**No value in `content/tuning.toml` was changed, and that is worth recording**, because
`heat.decay_per_minute` was the obvious lever and it was the wrong one. Raising it from 240 to
340 does flatten the Heat curve and did land the 20-40 minute window — but it also makes the
first three or four Machines completely silent, which takes away the half of the lesson that
happens in the first five minutes. What a Factory *makes* is unchanged; what a given Heat
*buys the Enemy* is what moved.

No value in `machines.csv`, `recipes.csv`, `gear.csv`, `deliveries.csv` or `stratagems.csv`
moved either — some of their comments now carry what was measured, which is the point of
having them — and **no code in `sim/` or `game/` changed at all**. The things that wanted
changing and were not numbers are below.

### What collision cost the two sorties

**#30 made the Factory solid after #26 measured it, and the two rows whose player walks
anywhere moved.** Recorded here rather than quietly re-measured, because the *reason* is the
interesting part and the figures above are only evidence while somebody can re-derive them.

`hive_sortie` broke outright. A scenario is a function from tick to Input Actions and cannot
look at the Simulation, so its walk is open-loop arithmetic: a heading, a held throttle and
`_sprint_ticks_for` to say when to let go. The straight line from the Nest to the eastern Hive
passes through the Smelter at (8, 4). What collision does to that walk is not a stop — the
player slides along the housing and comes out of it pointing somewhere else — so the sortie
arrived two seconds late, twelve metres short, and spent its thirty seconds of wrench swinging
at air. The measured consequence was a Run with two Hives still standing, and
`test_balance.test_clearing_a_hive_lengthens_a_run` caught it.

The fix is the one a player would make: go round. `SORTIE_WAYPOINT` is (24, 0) — east along the
Nest's own latitude until the Factory is behind him, then north-east to the Hive, and home the
same way. Both legs are clear ground, which is what keeps the open-loop arithmetic honest. The
walk is about 104 m rather than 90, and the Run is **29m36s against #26's 29m37s**: one second,
which is the right size for an answer to "what did a 14 m detour cost". The claim it was
measuring — clearing a Hive lengthens a Run — is unchanged.

`rifle_picket` was not re-routed and moved much further: **26m32s against 24m59s** at the time
of that measurement, and its cause changed from *swarmed* to *ran dry*. (#35's schedule has
since moved it again, to 26m52s, and flipped the claim it was guarding — see "What the shorter
first Wave cost", below.) Nothing about the scenario changed; it walks to
(-3, -3) beside the Nest and fires down the lane the Breach feeds, and with the Nest solid the
player's open-loop overshoot now settles somewhere slightly different, which moves where every
one of his rounds goes for the rest of the Run. **The claim still holds and its margin is
thinner**: a rifleman still shortens the Run against `competent`'s 27m00s, by 28 seconds rather
than by two minutes. That margin is now small enough that it is worth knowing it is the
assertion in `test_the_rifle_at_the_nest_is_a_fourth_claimant_on_one_ammo_press`, and a later
Ammunition change could flip it. If it flips, the honest response is the same as #26's: say
what was measured, not what was expected.

**No balance number was changed to accommodate any of this.** `content/waves.csv` and
`content/tuning.toml` were exactly as #26 left them; the one subsequent change to either is
#35's `heat.first_wave_interval_seconds`, which is below and was itself measured rather than
argued.

### What the shorter first Wave cost

**#35, and the one place the playtest's nine reports touched balance.** The report was
*"crawlers dont seem to be coming"*, which was not a bug: `heat.wave_interval_baseline_seconds`
doubled as the opening gap, so a new player waited 150 seconds in silence for the most
interesting thing in the game. `heat.first_wave_interval_seconds` separates them, and the
figure came out of this harness rather than out of an argument.

**50 was measured first and was wrong, in a way worth recording.** `deep_digger` went from
10m48s to **2m46s** — wave 3, peak Heat 25, browned out for 97% of the Run. That scenario pulls
the call-early lever once a minute from minute one, and a natural Wave arriving at 45 seconds
lands *in front of* the first pull, so the levers stack Waves onto a Factory that has not made
a round yet. The general lesson is the shape of the number rather than the number: **the
opening gap has to outlast the first thing a player can do about it**, and the first thing a
player can do about it is the lever.

At **90** the natural Wave still falls after the first minute. Measured against #34's column —
which is the right comparison now, since this branch was merged on top of it — the change costs
exactly what its shape predicts:

| Scenario | #34 | merged | #35's doing |
|---|---|---|---|
| `bare` | 4m22s | 3m22s | −60s |
| `opening_line` | 4m04s | 3m12s | −52s |
| `competent` | 29m07s | 28m48s | −19s |
| `over_producer` | 20m21s | 20m21s | — |
| `fortified` | 28m45s | 28m45s | — |
| `deep_digger` | 10m48s | 10m48s | — |
| `hive_sortie` | 32m22s | 32m05s | −17s |
| `rifle_picket` | 27m16s | 28m02s | **+46s** |

The two undefended rows lose a minute, because the first Wave is the only Wave they see. Three
rows do not move at all: a Factory that dies at minute twenty never notices where the first Wave
started. The long rows lose under twenty seconds. Nothing in `content/waves.csv` was touched, so
the curve #26 measured is intact and what moved is only where it starts.

`rifle_picket` going the *other* way by 46 seconds is the one figure here that is not obvious,
and it is the same mechanism as everything else in this row's history: moving the schedule's
phase moves where every round the picket fires goes, and this time it moved them somewhere that
bought time rather than cost it.

**And building is still what summons it**, which is why this is a shorter first *interval*
rather than a fixed opening timer. `opening_line` carries 615 Heat by its first Wave, which at
`heat.per_second_sooner` takes about 25 seconds off the 90 — so a player who builds the opening
line meets Crawlers at around 65 seconds and one who builds nothing waits the full 90. That is
the mechanic's own lesson arriving in the first minute instead of the third, and
`test_heat.test_a_factory_that_produces_meets_its_first_wave_sooner_than_an_idle_one` pins it.

**`rifle_picket`'s sign has now moved four times, and that is the finding.** #26 measured a
rifleman at the Nest costing two minutes. #30's collision took it to 28 seconds. #34's Breaker
approach took it back out to 1m51s. Measured on #35's own branch it crossed zero — 26m52s
against `competent`'s 26m42s, ten seconds the *other* way. **Merged, it is 46 seconds and back
on the original side**: 28m02s against 28m48s.

Four tickets, four signs or magnitudes, and **not one of them changed anything about the
Ammunition economy.** The mechanism #17 asked about is still real and still arithmetic: a Bolt
Rifle spends 75 rounds a minute out of a store a Press fills at 37. What the harness cannot do
is turn that into an end-to-end cost, because the quantity it would be measuring is smaller than
the phase noise of a schedule that other tickets keep re-phasing. So
`test_the_rifle_at_the_nest_is_a_fourth_claimant_on_one_ammo_press` asserts the claim the
figures actually support — a rifleman is **neither free nor ruinous**, within 90 seconds of
`competent` either way — and a later Ammunition change that made the rifle genuinely cheap or
genuinely fatal fails it. **Do not re-tune Ammunition off this row's margin**; it is not
measuring what it looks like it is measuring.

### What #34 cost the table

> **Read this as the record of one step, not as the current figures.** Every number below is
> #34's column in the table above, measured on #34's own branch against #26's. #35's first-Wave
> interval then merged on top and moved five of these rows again — see "What the shorter first
> Wave cost" for that delta and the **merged** column for where they actually stand. The two
> claims here that the merge changed in kind rather than in degree are `rifle_picket`, whose
> 1m51s is now 46s and whose *sign* has since moved twice more, and `fortified`, whose
> twenty-two-second margin is now three seconds. The reasoning is what this section is for and
> the reasoning is unaffected.

**#34 changed where a Breaker walks and nothing else, and it moved six of the eight rows.** No
number in `content/waves.csv` was touched and the one number it added — 
`enemy.breaker_breaks_ranks_within_tiles` — is geography expressed as tuning rather than a
balance lever. Recorded here in the same shape as #30's entry, because the *reasons* are the
part worth keeping.

The mechanism is in the flowfield section: a Breaker now steers by the Nest's field until it is
within eight tiles of the Nest or of a Machine, and by the Factory's field from there on. What
that does to a Run:

- **`competent` gained 2m07s and changed what killed it, which is the whole ticket.** 27m00s to
  **29m07s**, and from "ran dry, then the Breakers took the Factory" to "three Siege Hulks, with
  96 rounds still in it". The Factory now holds all six Machines through the entire Breaker tier
  — the lane MG engages a Breaker for the ten seconds of road and turn it has to cross — so the
  Heat it keeps making carries it past `siege_hulks.min_heat` of 6400, which **no measured Run
  had ever reached**. The old ending was a rule a player could not see; the new one is a boss
  that walks in, halts, shells, has its impact point drawn on the HUD, and is answered on foot.
- **`hive_sortie` is now the longest Run measured**, 29m36s to **32m22s**, +3m15s over
  `competent` where it used to be +2m36s. The sortie's reward grew because what it buys — 30 of
  the Nest's Heat decay, permanently — now buys *time before the boss* rather than time before
  the Breakers. A Factory that defends itself turns Heat into the binding constraint, and a
  Hive is the only thing in Milestone 1 that moves it.
- **`fortified` is now a wash, and that is the fix landing rather than failing.** 29m15s to
  **28m45s** — twenty-two seconds *shorter* than `competent`. Its second MG at (11, 6) existed
  to cover the Factory because a Breaker would not come to the lane; now the lane Turret does
  the job, so the second one buys kills the first one would have made while costing 90 kW of
  draw, a share of one Press's output and the Heat that goes with them. It ends with 112 rounds
  unspent, which says the same thing from the other side: **Ammunition was never the constraint
  for either row.** The honest reading is that `fortified`'s row was measuring the workaround to
  a bug, and the workaround is now worth nothing.
- **`over_producer` and `rifle_picket` both moved by about forty-five seconds** and both claims
  got *stronger*. Over-producing costs 30% of the Run rather than 27%; the rifleman costs 1m51s
  rather than 28s. Same reason in both cases: a Factory that keeps its Machines has further to
  fall, so the thing it wasted is measured against a longer Run.
- **`bare`, `opening_line` and `deep_digger` did not move at all.** None of them reaches
  `shock_breakers.min_heat` of 5200, so none of them ever met a Breaker. That is the control
  this change deserved: three rows that should not have moved, and did not.

**Two thresholds are worth re-reading in this light, and neither was touched.**
`shock_breakers.min_heat = 5200` was set where it is because a Breaker was unanswerable, and it
is now answerable — so the question it asks arrives late, and a later ticket could reasonably
bring the Breaker tier forward to where it is the mid-game pressure rather than the last five
minutes. And `siege_hulks.min_heat = 6400` was set by #26 to be "reachable only by a Factory
that kept its Machines alive and its Turrets fed", which was unreachable in practice precisely
*because* of the bug #34 fixed. It is now reached by four rows. **That number is not newly
wrong; it is newly doing what it was tuned to do**, and moving it to put the boss back out of
the harness's sight would be tuning for the instrument rather than for the game.

### What #37 cost the table

**#37 changed two rules and added a ninth row, and the eight rows of record did not move by a
single tick.** That is worth as much as the new row is: both changes are about failure modes the
table could not see, so a table that *had* moved would have meant one of them had a side effect
nobody asked for.

> **Read the `artillery` figures below as #37's column**, not as current ones. #46's branching
> Belts gave the Silo an equal share of the Ammo Press instead of the Turret's overflow and the
> row is now 15m22s; see "What #46 cost the table". The reasoning here is unaffected.

**The new row is the acceptance criterion.** `artillery` is `competent` plus four Machines, four
Belts and a Silo that gets loaded and fired — 16m10s, Wave 21, one Stratagem called in on two
Charges with nothing wasted, and 8 Charges banked at the peak, which is the Silo's whole
`charge_capacity`. Three things it settles:

- **A Milestone 1 Run can power a Silo, and nothing in `content/` had to change.** A second
  Boiler on the one coal Node is worth about 800 kW of average supply rather than 600, because a
  Boiler is on the grid only while it burns. See "The one Power grid" for the arithmetic and
  "The Silo… Where the balance stands" for what #26 read instead.
- **What it costs is the Run, not the rounds.** 16m10s against `competent`'s 29m07s is 44% of
  the Run, and the Ammunition was never the binding constraint: 298 shots fired, 52 rounds
  still in the Factory, and a Silo that filled to capacity. What it actually paid was **seven
  pulls of the call-early lever** for ninety-six plate, and **31% of the Run in Power deficit**
  with 1,060 kW of demand against about 1,100 kW of average supply. Artillery is a Factory
  running flat out, which is exactly the standing the Heat system is built to punish.
- **Plate is the bottleneck nobody had measured.** A Silo's Recipe is a plate and twenty rounds,
  and the Smelter makes 18.75 plate a minute against an Ammo Press that wants 20 — so a second
  Belt off that Smelter is served *after* the Press's by canonical Belt order and never gets a
  single plate. The Silo's plate has to be **made** rather than diverted, which is why the row
  builds a second Miner and Smelter on the spare iron Node. That is the opposite of the
  twenty-rounds-a-Charge worry #26 recorded.

**The Nest's store fix moved nothing measurable, and the reason is the row that was supposed to
show it.** `deep_digger` tears its coal Belt down at three minutes, so it never spent long
against the store's cap. Measured with that demolish *removed*, the Run is **6m20s with 98% of
it in Power deficit** — which is #26's finding reproduced, and the store is no longer most of
it: forty tiles of Belt hold 160 coal of their own before back-pressure reaches the Miner, and
that line's entry precedes the Boiler's in canonical Belt order so it is served first. So the
store's 200 is gone and 180 remain, which is the new finding below rather than a fix that failed.

### What #46 cost the table

**#46 changed how a Machine shares its output between two Belts and nothing else, and it moved
two of the nine rows.** No number in `content/` was touched and no tuning key was added. All nine
scenarios were re-measured unchanged, on the merged tree, so the delta belongs to the mechanic
alone — which is also why the seven rows that did not move are worth as much as the two that did:
a branch that makes no difference to a Run is a branch whose Belt was backed up anyway.

| Scenario | merged | #46 | #46's doing |
|---|---|---|---|
| `bare` | 3m22s | 3m22s | — no Belt at all |
| `opening_line` | 3m12s | 3m12s | — one Belt per Machine |
| `competent` | 28m48s | 28m48s | — one Belt per Machine |
| `over_producer` | 20m21s | 20m21s | — |
| `fortified` | 28m45s | 28m45s | — |
| `deep_digger` | 10m48s | **11m03s** | **+15s**, and Wave 12 on 2995 Heat against Wave 11 on 2565 |
| `hive_sortie` | 32m05s | 32m05s | — |
| `rifle_picket` | 28m02s | 28m02s | — its branch was already backed up |
| `artillery` | 16m10s | **15m22s** | **−48s**, Wave 20 on 4906 Heat against Wave 21 on 5584 |

- **`deep_digger` got *longer* by sharing its coal, which is the fix landing.** That Run builds a
  forty-tile coal Belt to the Nest to pay `t02_deep_mining`, and finding 8's third consequence was
  that the Belt's entry tile at (12, 6) *precedes* the Boiler's at (14, 4), so the Nest's line was
  served first every tick and the Boiler burned what was left. The Boiler now gets half, and the
  measured consequence is a Factory that spends **17% of the Run in Power deficit** instead of
  browning out behind a line it cannot see: more throughput, 17% more peak Heat, a Wave further
  into the schedule — **and fifteen seconds longer anyway**, because a Turret that is fed outlives
  the Heat it costs. It still reaches Depth 2 and still opens its second Breach, so what the row
  measures is unchanged.
- **`artillery` got shorter by sharing its rounds, and that is the row paying a price it was
  always supposed to pay.** The Silo's Ammunition line and the Turret's both come off the one Ammo
  Press, and the Silo's entry at (7, 11) comes *after* the Turret's at (7, 9) — so before #46 the
  Turret was fed first and the Silo took only what sixty rounds of Belt could not hold. The Silo
  now takes half. It still banks enough: **7 Charges at the peak against a capacity of 8, and the
  same one Stratagem fired on two Charges with none wasted.** What it no longer has is the
  Turret's share — 32 rounds left in the Factory at the end against 52 — and the Run is 48 seconds
  shorter, **47% of `competent` rather than 44%**. Power went the same way, 36% of the Run in
  deficit against 31%. The honest reading is the one #17 asked for and #37 could only half answer:
  **artillery and the magazine spend the same output, and now they really do split it.**
- **`rifle_picket` has a branch and did not move at all**, which is the control that keeps the
  `deep_digger` attribution honest. It runs the same second Belt off the Ammo Press to the Nest
  that `deep_digger` does; its Run length, Wave and peak Heat are identical to three seeds. An
  Ammunition line into the Nest fills the store and then backs up, so over a Run its share is the
  same either way — the priority only ever showed in the minutes before it filled. So
  `deep_digger`'s fifteen seconds are the *coal* branch, not that one.
- **Two Boilers on one coal Node now cycle together instead of one running flat out.** 40 coal a
  minute against two appetites of 30 used to be one Boiler burning continuously and the other a
  third of the time; it is now two Boilers each burning two thirds of the time. The grid cannot
  tell the difference and #37's 800 kW of average supply is untouched — but it is what a player
  sees, and it is the clearest small example of what this ticket did.

**No balance number was changed for any of this**, and the two moved rows are not an argument for
changing one. `artillery` losing 48 seconds is the Silo being charged properly rather than the
Silo becoming too expensive, and `deep_digger` gaining 15 is a trap getting slightly less sharp.

### What the seed can reach

**A Run length here is a function of the Factory and not of the seed, and that is a property of
the Simulation rather than of the harness.** The Map is handcrafted (`MapLayout.starter()`
consults no seed), the Wave schedule is a function of Heat, and the single consumer of the
seeded RNG in the whole of `sim/` is `Simulation._scatter` — the spread on a *ranged* shot. So
three seeds are three identical Runs, down to which Machines were lost in which order, and
`test_balance.test_a_run_length_is_a_function_of_the_factory_and_not_of_the_seed` asserts
exactly that.

Two consequences worth knowing before anybody quotes a variance:

- **The three seeds in the measurement are a demonstration, not a sample.** There is no
  distribution to sample until a player opens fire — and `rifle_picket` is the one row that
  does. #26 measured it identical across all three seeds; with #30's collision in it was 26m32s
  on seed 7 against 26m29s on seeds 11 and 29; on #35's branch it spread eleven seconds. **On
  the merged schedule the spread in Run length is back to zero**: 28m02s on all three seeds, and
  the only figure that still differs is peak Heat — 6186, 6178 and 6174. That is the claim in
  its clearest form yet. The seeded RNG moves *where the rounds go*, which moves how much Heat
  the Factory had made by the end, and it does not move how long the Nest stands. Every row in
  the table is now bit-identical across seeds in end tick, and
  `test_balance.test_a_run_length_is_a_function_of_the_factory_and_not_of_the_seed` asserts that
  on `competent`.

  Worth not over-reading: the spread going to zero is not an improvement anybody made. It is
  where this schedule's phase happens to put the last Wave, and the next ticket that re-phases
  the schedule may well split the three seeds again. The *property* — scatter moves rounds, not
  Run length — is the thing to hold on to, and it is what the test asserts.
- **`Simulation.hash()` cannot be used as the evidence**, which is a trap worth naming because
  it looks like it should be: the hash feeds `_rng.state`, which is seeded, so two seeds differ
  in hash from tick 0 whether or not a draw is ever taken.
  `BalanceProbe.Report.figures()` is what two seeds are compared on.

### Findings that are not tuning

The things the measurement turned up that a number cannot fix. None was patched; all are
recorded here instead, which is what #26 asked for.

1. ~~**A Turret on the Nest's lane cannot defend the Factory.**~~ **Fixed by #34**, and the
   only one of these findings that has been. A Breaker steered by the Factory flowfield and a
   Crawler by the Nest's, so a Breaker never entered the reach of a Turret placed to cover the
   Nest: the documented `competent` Factory had *no answer at all* to the Breaker tier and lost
   all five production Machines in its last minutes, while `fortified` outlasted it by two
   minutes purely because its second MG happened to stand over the Factory rather than the lane.
   #26 recorded it rather than patching it because it is geography and not a number — and the
   fix is geography: a Breaker now marches the Nest's field until it is within
   `enemy.breaker_breaks_ranks_within_tiles` of the Nest or of a Machine, and hunts from there.
   See the flowfield section for the mechanism and "What #34 cost the table" for what it did to
   all eight rows. The lesson the trap replaced: **a Breaker comes down the road, under fire,
   and lunges at the first thing you built beside it.**
2. ~~**A Belt into the Nest banks the surplus for ever, so a Belt nobody tears down is a
   permanent tax.**~~ **Fixed by #37**, and the fix is the rule this project already had: the
   Nest refuses what it has no room for and the Belt packs up. What was missing was a reason for
   the store to have no room, and it is that **coal is not something a player can spend again**.
   `t01_munitions` wanted 20 coal and the store would then take 200 more — a Factory's own fuel
   converted into a number nothing in the game has a sink for, which is the opposite of what the
   store is for. Now the bill takes its 20 and the next lump is refused, so the diversion ends
   itself in seconds instead of running for the length of a Run. See "The Nest's store, and the
   faucet it is". The lesson the trap replaced: **the Nest banks what you could spend, and
   nothing else; everything else backs up where you can see it.**
3. ~~**Milestone 1 cannot power a Silo.**~~ **Fixed by #37, and it turned out not to be a design
   question at all.** The arithmetic was a count where it should have been a rate: a Boiler is on
   the grid only while it is *burning*, so one coal Node's 40 coal a minute is 1.33 Boilers
   burning rather than one Boiler burning and 10 coal a minute piling up on a Belt. Two Boilers
   on one Node supply about 800 kW averaged over time, and 300 + 800 against 660 leaves room for
   a Silo's 400. No second coal Node, no second generator class, **no number changed** — the
   Power was always there to be built toward, and the `artillery` row is the Run that builds
   toward it. #17's question is now asked and answered: a Silo does *not* stop a Run feeding its
   Turrets, because what it actually competes for is plate and Power.
4. **The Siege Hulk's frontal arc is not expensive, it is very nearly immune.** 85% off 15
   leaves an MG doing 2, and off a Bolt Rifle's 30 leaves 4 — so 1800 hit points is 900 Turret
   rounds or 450 rifle shots from the front. DESIGN.md says the Hulk must be answered on foot,
   and it means *from behind*. That is a legitimate design position, but it is also the one thing
   this harness cannot measure: an open-loop scripted session cannot walk a circle around
   something that is walking towards it.
5. **"Over-produced" is not a verdict a report can earn.** `BalanceProbe.cause` had a clause for
   it — the Wave interval pinned at `heat.wave_interval_minimum_seconds` for most of the Run —
   and it fired on *every* Run over about twenty minutes, careful and careless alike, because
   the net Heat of any working Factory outruns what the Nest can hide. It was removed. Over-
   production is legible as a shorter Run, which is the only form in which it is informative.
6. **A `move` intent is consumed every tick and a `sprint` is not.** Not a bug — `_walk`'s own
   comment says standing still is the absence of an intent rather than an intent of its own —
   but it is the kind of asymmetry that costs an hour to find, and it is why
   `BalanceScenarios._walk_to` holds the throttle across the whole span of a walk and sends the
   look and the sprint once.
7. **`heat.wave_interval_baseline_seconds` is a fixed-point quantity of seconds**, like every
   decimal in `tuning.toml`. Reading it as a whole number — which the first draft of
   `BalanceProbe` did — yields 9,830,400 and an "at the interval floor" verdict that is always
   true. Anything reading a `_seconds` field off `Definitions` goes through `Fixed.floor_to_int`
   or the same `Fixed.mul` the Simulation uses.
8. ~~**A splitter in this game is a priority, not a half-share.**~~ **Fixed by #46**, which is
   the ticket this finding said it belonged to. `_load_from_port` used to be called per Belt from
   inside `_advance_belt`, so a Machine with two Belts off it filled the first one that had room
   *every tick* and the two only alternated when the first was backed up. Three consequences were
   measured and all three are now gone: the Ammo Press fed its Turret line and the Silo got only
   what that line could not hold; **a second Belt off the Smelter never received a single plate**,
   because the Press took the lot, which is why `artillery` had to build an entire second ore
   line; and `deep_digger`'s coal Belt to the Nest was served **before** the Boiler's purely
   because its entry tile had a smaller x, which was the invisible part of the starvation #37
   fixed the visible part of. (The sentence that claimed the Press "alternates" between two lines
   was wrong and #37 corrected it.)

   The fix is the shape this finding named: **"which Belt was served last" as hashed state in the
   one function every Belt goes through.** Loading became a pass of its own, after every Belt has
   advanced, and `_machine_port_cursor` — one integer per Machine, hashed — rotates which branch
   gets first claim. The list it indexes is the Machine's Belts in *canonical* order, so the
   share is geography plus one integer of history rather than build order. See "A line that
   branches, and the rotation that makes it one". The lesson the trap replaced: **two Belts off
   one Machine both run, and what neither can carry banks in the Machine where you can see it.**
9. **A long Belt is a long buffer, and a Belt pointed at the Nest hides its diversion inside
   itself.** `deep_digger`'s coal line is forty tiles, which is 160 coal before back-pressure
   reaches the Miner at all — eight times what the tier it was built to pay actually wanted.
   With the demolish removed the Run was 6m20s and 98% browned out even with #37's store fix in.
   **#46 blunted it rather than closing it**, and neither figure has been re-measured on the fair
   share: the line now takes half the Miner's coal while it fills instead of all of it, which is
   what moved `deep_digger` itself from 10m48s to 11m03s and its Power deficit down to 17% of the
   Run. Unlike the store this is at least *visible* — it is a Belt packed solid with coal — and it
   is bounded by something the player built rather than by a number in `tuning.toml`. But "I ran a
   Belt to the Nest and my Factory browned out for half the Run" is still a lesson nothing says
   out loud, and the HUD is where it would be said. **Re-measuring the demolish-removed variant is
   the cheap half of that ticket.**
10. **"The Turret ran dry" has to be measured on the Factory, not on the Turret.** A destroyed
   Turret holds no rounds and contributes no ticks, so a per-Turret ratio reports 0% for the
   most common ending there is: the Ammunition ran out, and then the Breakers ate the Turret.
   `DRY_ENDGAME_PERCENT` is measured against "no Ammunition anywhere in the Factory".

### What is still unmeasured

Honest residue, so the next ticket does not have to rediscover it:

- **Anything that is about feel through a mouse.** `gear.view_kick_degrees_per_shot`,
  `gear.enemy_hit_radius_metres`, `silo.paint_seconds`, and whether a player *hesitates* before
  leaving the Factory. A harness has no opinion about any of them.
- **Hand repair under fire.** No scenario picks up a wrench to save a Machine, because chasing a
  Breaker open-loop is not possible. `wrench.repair_points_per_second` against
  `enemy.breaker_damage` is still an arithmetic claim.
- **Walls.** Nothing in the nine scenarios builds one, so `wall.health` against
  `enemy.breaker_damage` is likewise unplayed.
- **Two of the three Stratagems, and the Painting's length.** The Silo itself is measured now —
  `artillery` powers one, loads it and fires it — but what it fires is a **Sentry Drop**, because
  that is the one row the shipped Delivery chain does not lock: `supply_drop` sits behind
  `t02_deep_mining` and `artillery_barrage` behind `t03_deep_survey`. So a Barrage's 150 points
  over six tiles and a Supply Drop into a player's own pockets are still arithmetic, and so is
  `silo.paint_seconds` — five seconds of being helpless is the whole feel of the mechanic and a
  three-second Sentry Drop is not the same question. **The next scenario worth writing is
  `deep_digger` with a Silo**, which is the only Run that reaches a Barrage at all.
- **Answering a Siege Hulk on foot**, for the flanking reason above — and it is now the single
  biggest hole in the table rather than a footnote. Before #34 no scenario reached 6400 Heat at
  all; now **four of them do**, and all four end with Siege Hulks standing that nothing they own
  can hurt. Every Run over twenty minutes therefore ends the same way, which compresses the
  differences between builds at the top of the table and is a harness limitation rather than a
  balance fault: the Hulk's answer is a player walking behind it, and an open-loop scripted
  session cannot walk a circle around something that is walking towards it. **The next thing a
  human should play is `competent` from minute twenty-five with a rifle in their hands.**
- **A second Ammo Press**, still. The Turrets section says it is the answer to minute thirty and
  nothing measures it — and #34 sharpened the question rather than answering it: `competent` now
  ends with 96 rounds unspent and `fortified` with 112, so **one Turret cannot spend what one
  Press makes**, and the plate the lever pays is better spent on throughput than on a second
  Turret. Which of the two a second Press and a second Turret *together* fixes is unmeasured.
- **A branched Factory, which is the Run #46 made possible and none of the nine measures.** Every
  scenario is the Factory a player would have built *before* a line could branch. The sharpest
  missing row is `artillery` **without** its second ore line, feeding the Silo's plate off a
  branch of the first Smelter instead: it would save 20 plate and two Machines' worth of Heat and
  Power, at the price of halving the Ammo Press while the Silo's branch is filling. The arithmetic
  says it works — the Silo wants 3 plate a minute out of 18.75, so its branch fills, backs up, and
  hands the Press everything back — but arithmetic is what this harness exists to replace, and
  **the second ore line is still the only build measured.** Shipped-content branching itself is
  asserted, in `test_belts.test_the_shipped_smelter_can_feed_two_consumers_at_once`; what is not
  measured is a whole Run built around it.
- **Whether a long Belt to the Nest is still a trap, on a fair share.** Finding 9's 6m20s was
  measured when that line took *all* the coal. See it for what is cheap to re-measure.
- **Co-op.** Every scenario is one player. Four players on one Ammo Press is a different
  economy, and the Simulation already supports measuring it.

## Shipping a build

`bash tools/release/build_windows.sh` is the whole of it;
[docs/RELEASING.md](docs/RELEASING.md) is the one-time setup and the reasoning. Two
things in there are worth knowing before touching anything near an export.

**A `.gdignore` hides a directory from the *exporter* as thoroughly as from the
importer, and this project has two of them.** `content/.gdignore` stops Godot
claiming every `.csv` as a translation table and `assets_licensed/.gdignore` stops
it walking seven gigabytes of purchased WAV — and the first export of this project
consequently contained **zero rows of `content/` and zero of the 96 licensed
files**, while still producing a 130 MB executable that ran. So the build exports a
**staging tree** (`tools/release/stage.py`): the project rsynced, only
`generated/` copied out of the quarantine, both markers deleted in the copy, and an
`importer="keep"` sidecar beside every affected file so the exporter stores raw
bytes at raw paths. The working copy is never touched.

**The failure mode is silence, so verification is the deliverable.** Weapon
viewmodels, audio cues and set-dressing props each degrade gracefully, which is
right for a clone and a trap for a release: a build that lost them looks worse,
sounds worse and says nothing. Four gates, each naming the converter to run —
`preflight.py` against the quarantine, `verify_pck.py` against the shipped
binary's own pack index, `verify_bundled_assets.gd` opening that pack with
`--main-pack` and counting what the game's own classes *resolved*, and the real
`.exe` started through WSL interop for 240 frames with its log read for errors.
The last two are both needed: the index cannot tell a loadable file from an
unloadable one, and the loader cannot tell you which file is missing.

Three facts that cost time to find: **`--script` does nothing in a release
template** (the engine starts the main scene and never returns), the licensed
assets go **inside the PCK and never loose beside the binary** because that is the
line the licences draw, and **icon/version embedding is skipped on purpose** —
it needs rcedit under Wine, which is per-machine state the repo cannot carry, and
there is no icon art to embed yet.

## The float-to-fixed boundary

ADR 0002 says nothing converts a float back into a Simulation quantity. A first-person
controller cannot honour that literally — a mouse reports pixels as floats and a camera ray
is float arithmetic — so the crossing is made **exactly once**, in
`game/input_quantiser.gd`, under three rules:

1. **It lives in `game/`, never in `sim/`.** The purity lint takes no new exemption for it,
   because it is not in the Simulation.
2. **What crosses is an integer intent.** Mouse travel becomes a floored fixed-point count
   of pixels; a camera ray becomes a whole tile. A replay reproduces the intent without
   ever reproducing the float.
3. **Flooring, clamping and NAN-guarding are explicit.** Every conversion floors toward
   negative infinity like `Fixed`, every conversion is bounded, and NAN and INF are reduced
   rather than cast — NAN compares false against everything, and an unguarded cast would let
   it through as an arbitrary integer and desync a Run.

It has a contract of its own in `tests/cases/test_input_quantiser.gd`, like `Fixed`, because
its rounding is not observable through the façade. If you need to read a new float device,
add a function there rather than converting at the call site. #15 did exactly that:
`aimed_tile_at_height` is the Pneumatic Wrench's aim, which crosses the *body* of a Machine
rather than the ground the Build Gun's hologram snaps to.

**Firing crosses nothing, and that is the rule honoured rather than dodged.** A player's yaw
and pitch are already authoritative fixed-point state, so where a round goes is something the
Simulation knows exactly; an aim carried in a `FIRE` intent would be a second opinion derived
from a float. See the Gear section above.

`game/player_controller.gd` holds the only other float on the way in: a **device buffer**
of mouse travel and clicks gathered between frames. That is the same category of thing as
`TickPump`'s leftover frame time — a reading on its way in, not a fact about the world —
and it is drained once per tick. Everything a decision depends on is read back out of the
Simulation with a query.

## Determinism rules

From [ADR 0002](docs/adr/0002-deterministic-lockstep-inputs-only-networking.md).
Inside `sim/`, all four are absolute:

1. **Fixed-point integers only.** No floats in state or in intermediate steps.
   `Fixed.to_float` is the single sanctioned crossing and is outbound only.
2. **No wall-clock time.** The Simulation knows which tick it is on and nothing
   else. Deciding *when* to step belongs to `game/tick_pump.gd`.
3. **No unseeded randomness.** `DeterministicRng`, seeded at construction, is the
   only source. Never `randi()`, `randf()` or `RandomNumberGenerator`.
4. **No iteration over an unordered collection.** Arrays indexed by id, in index
   order. Sort keys first where a Dictionary is unavoidable.

`tests/cases/test_simulation_purity.gd` enforces all four mechanically against
every file in `sim/`. To take a sanctioned exception, put
`# purity-ok: <reason>` on the offending line. There are three in the whole
Simulation; the test fails if that count drifts far upward.

## Adding state to the Simulation

Feed it into `hash()`. State that is not hashed is state whose divergence the
determinism harness cannot see, which quietly weakens the guarantee the whole
architecture rests on.

**That is the only thing you have to do.** You do not have to remember to save it:
`sim/run_save.gd` walks the Simulation's own property list and persists every
script variable it finds, so a new `var` is saved, loaded and round-tripped
without that file changing. See below.

## Saving and resuming a Run

`sim/run_save.gd` is the whole of it, and its promise is one sentence: **a Run
written out and read back hashes to the integer it hashed to before.** Because
`hash()` already covers everything that matters, that single comparison is the
entire acceptance criterion, and `tests/cases/test_run_save.gd` asserts it over a
Factory with Items in flight, a part-finished craft, a grid in deficit and a player
mid-stride.

- **There is no list of fields and no per-field code.** `RunSave` reflects over
  `Simulation.get_property_list()`. Forgetting to persist new state is therefore
  not a mistake that can be made — the one `# purity-ok:` line that reflection
  costs buys that outright. `test_run_save.gd` proves it with a `Simulation`
  subclass carrying Enemy arrays `RunSave` has never heard of, which round-trip
  anyway.
- **Two special cases, named in that file and nowhere else.** The `Definitions`
  (carried as a digest; content lives in `content/`) and the `DeterministicRng`
  (whose whole memory is one integer).
- **The file is a census and the load checks it.** Every property gets a line, and
  loading compares the file's names against the live Simulation's. A save written
  before an array existed refuses *by name* rather than resuming with it quietly
  empty. So does one carrying a property this build no longer has.
- **The save carries its own state hash and every load re-derives it.** Any failure
  to round-trip exactly is caught on every load a player ever performs, not only in
  the suite.
- **A property in a type the format cannot encode is refused by name**, not
  silently zeroed. Hold state as parallel integer arrays — which is the convention
  anyway — or teach `_encode_value` about the type.
- **`RunSave.DERIVED_PROPERTIES` is the one exception to "every property".** The
  flowfield is one entry per tile of the Map three arrays over, so carrying it would
  make every save hundreds of kilobytes of numbers the next tick recomputes, growing
  with the square of the Map rather than with the Factory. Excluding a property is safe
  only because the names on that list are **absent from `hash()`** too, which is what
  leaves the round-trip check with teeth — so check `hash()` before adding to it. A
  restored Run notices it is holding no field by its size rather than by a flag, and
  `test_enemies` steps a saved and a resumed Run side by side to prove the rebuild
  agrees.
- **The format is line-oriented text**, `<property> <type-tag> <payload…>`, keyed by
  name rather than by position. Chosen for diffability in a project whose method is
  comparing two states, and because a positional blob cannot report which field it is
  missing. The rationale, and the escape hatch if size ever becomes the constraint,
  are in the file's own header.
- **Saving is a read.** It takes no action, consumes no RNG draw and leaves the hash
  alone, so a Run saved mid-flight follows exactly the ticks it would have unsaved.
- **Rendering state is never saved** because there is none: `WorldView` rebuilds from
  `query_*` every frame and holds nothing authoritative.
- **Neither key is an Input Action.** `PlayerController.KEY_SAVE` (F5) and `KEY_LOAD`
  (F9) are handled in `Main._input` alongside Escape. Saving does nothing to the Run;
  loading *replaces* the Simulation, which no method on it could do and no replay
  could reproduce — resuming a Run is the same category of act as constructing one.
  The full argument is written above `PlayerController.KEY_SAVE`. Contrast
  `RELOAD_DEFINITIONS`, which is an action because it mutates the Simulation that
  exists, at a known tick.
- **A refused load leaves the running Run untouched**, the same rule a failed
  hot-reload obeys.

Every later ticket should carry a round-trip criterion, and the cheapest way to
write one is a hash comparison through `RunSave.serialise` / `deserialise` — or
`DeterminismHarness.verify(recording, restored_sim)`, which takes a replacement
Simulation for exactly this.

## The determinism harness

`sim/determinism_harness.gd` records a script of Input Actions, replays it from an
identical starting state, and compares the state hash **tick by tick** — not just
at the end, because a fault that perturbs a few ticks and settles back is still a
desync.

Every subsequent ticket is expected to leave a replay fixture behind:

```gdscript
var script: InputScript = InputScript.new()
script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
script.add_idle_ticks(30)

var recording: ReplayRecording = DeterminismHarness.record(script, seed, players)
var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
assert_true(divergence.is_identical, divergence.describe())
```

`record` takes an optional `Definitions`. Leave it out in a fixture: the replay
then re-reads `content/`, and a content change that would alter the Run is
reported as a `definitions_mismatch` rather than passing unnoticed. Pass one when
the scenario needs content the shipped files do not have.

`verify` takes an optional replacement Simulation, which is how a save/load round
trip gets proved exact and how the harness itself is proved to have teeth.

**A fixture is worth nothing without an honesty check beside it.** A replay of a Run in which
the thing never happened reads as a passing determinism test, and the failure mode is silent.
`test_gear.gd` established the shape and `test_silo.gd` leans on it hardest: its pair of
fixtures is a Charge assembled and **fired** and a Painting **interrupted**, and each has a
test that drives the same script and asserts the event rather than its absence — because an
interruption is exactly the kind of thing it is easy to conclude from an effect that failed to
arrive.

`tests/cases/test_recorded_session.gd` is the strongest fixture in the suite and the shape
later ones should copy: it drives the **real input producer** with a sequence of device
readings — mouse travel, held keys, clicks, a scroll wheel, Survey View held and released —
captures what crossed tick by tick, and replays that. A fixture written as Input Actions by
hand proves the Simulation is deterministic; one written as device readings proves the whole
chain from a mouse to a state hash is.

## Conventions

- Files and directories `snake_case.gd`; classes `PascalCase` via `class_name`.
- Tabs for indentation, as Godot's formatter expects.
- Static typing everywhere, including loop variables (`for i: int in ...`).
- Test files `tests/cases/test_*.gd` extending `TestCase`, methods `test_*`.
  Discovery and execution are sorted by name, so the suite is itself
  deterministic.
- Test names read as specifications — `test_a_turret_without_ammunition_does_not_fire`,
  not `test_turret_3`.
- Expected values in tests come from a worked example or a known literal, never
  from recomputing what the code does. `Fixed.mul(a, b) == (a * b) >> 16` asserts
  nothing.
- Domain vocabulary from `GLOSSARY.md`, capitalised: Nest, Breach, Factory,
  Machine, Belt, Heat, Wave, Turret, Silo, Charge, Delivery, Depth, Gear, Stratagem.
- Fixed-point constants are written `Fixed.from_rational(1, 3)`, never as a
  decimal literal. In a *data* file a rate is written in decimal and parsed with
  `Fixed.from_decimal_string`.
- **Every test method must assert something.** The runner counts assertions and
  fails a method that made none. If a test's happy path returns early, assert
  explicitly rather than falling off the end.
- **A method cut off by a runtime error fails, however far it got.** See the
  runtime-error guard below. A test that triggers one deliberately must claim it
  with `engine_log.drain()`, which is also the assertion that it happened.

## Test runner

Zero dependencies — no addons. The spec's first choice was gdUnit4; a
zero-dependency headless runner was its sanctioned fallback and is what shipped,
to avoid vendoring an addon into a public repository and to keep full control of
headless exit codes. There is no JUnit XML output yet; add it when CI needs it.

Two guards stop a method that did not really pass from reporting `ok`. Both exist
because the suite is the project's only guarantee of determinism, and a test that
reads green without having run is worse than no test at all.

**A method that asserted nothing fails.** That covers the empty test and the one
whose only statement aborted.

**A method cut off by a GDScript runtime error fails, naming the engine's own
error.** This is the harder half. A runtime error — a call to a function that does
not exist, an index out of range, a division by zero — aborts *only the frame it
fired in*: the caller resumes at the statement after the call, nothing is raised,
and every assertion that had already passed stays counted. So the assertion count
cannot tell a finished method from a severed one, and a method that aborts after
one passing assertion used to report `ok` with its untested remainder unmentioned.

Nothing in GDScript can catch such an error, so `tests/engine_log.gd` reads the
engine's *report* of it instead. Godot mirrors its output into
`user://logs/godot.log` and flushes as it goes, so the file is readable by the
process writing it; each runtime error lands there prefixed `SCRIPT ERROR: `,
which `push_error()` (`ERROR: `) and `push_warning()` (`WARNING: `) do not use, so
a test that deliberately drives production code into reporting an error is
unaffected. The runner resets the reader before every method and drains it after,
and records a failure per error — so detection does not depend on the depth of the
frame that died, and a method that ran to its end records nothing.

Consequences worth knowing:

- `debug/file_logging/enable_file_logging=true` in `project.godot` is load-bearing
  for the suite, not just for debugging. The runner prints its `Engine log:` line
  *through* the log and fails the whole suite if the line does not come back,
  because a guard that has quietly become a no-op is the exact failure it exists
  to prevent.
- A test that triggers a runtime error on purpose calls `engine_log.drain()` to
  claim it — the runner then finds nothing left and the method passes. Drain in
  the test method's own frame, not the aborted one, which it will reach because
  the abort killed only the callee.
- The guard's own tests are `tests/cases/test_runtime_abort_guard.gd`, covering
  both directions: an abort after a passing assertion must fail, and a method that
  completes must not. A guard that always fires and one that never fires are
  equally worthless, so neither case may be dropped.

### Run it through `tools/run_tests.sh`, and why that is not a convenience

The script does two things the engine will not do for itself. Both were found by
measuring a flake rather than by reasoning about one, and both had previously
been written off as "the cold-cache import race, aggravated by concurrent
agents". Neither was.

**It gives the run a private `user://`.** Godot derives the user data directory
from the project's *name*, so every worktree of this repo resolves `user://` to
one shared directory. That was already known for the engine log and fixed by
naming a private log file — but the fixtures that write there were left sharing.
`test_definition_watcher` creates `user://definition_watcher_test` in
`before_each` and deletes it in `after_each`, and the Run-save tests write save
files beside it, so a sibling checkout running its suite deletes the directory
between this one's `make_dir` and its `store_string`. The symptom is four
failures reading `Cannot call method 'store_string' on a null value` that do not
reproduce, because by the re-run the sibling has finished. Measured at one full
cold run in six with five to seven suites running at once.

The fix points `XDG_DATA_HOME` inside `.godot/`, which is per-worktree, so the
whole of `user://` moves rather than the three fixtures that happen to use it
today. `test_harness_self_check.test_the_user_directory_is_private_to_this_worktree`
asserts it took effect — a fix for a contention bug is invisible when there is no
contention, so without that assertion the suite would quietly go back to passing
alone and failing beside a sibling.

**It insists the import actually finished.** `godot --headless --import`
segfaults in the audio importer on roughly one cold pass in forty (measured: 2 of
80, always part way through the `.ogg` reimport, leaving `.godot/` holding six
files instead of the seven hundred a finished import writes). The runner used to
discard that with `|| true` and run the suite anyway. Restoring one of those
crashed caches byte for byte and running the suite gives **1162 passed, 8 failed**
— in `test_machine_meshes`, `test_world_view` and `test_game_audio`, every one of
them a missing import reported as a wrong answer, and every one of them green on
a re-run because the next pass finishes the job. That is where the "8 failures
that did not reproduce" came from.

So a failed import is now retried, and after the passes every destination
declared by a `.import` sidecar must exist on disk or the script exits 2 saying
which one is missing. **A suite must never run against a cache nobody checked**:
a missing import does not report as a missing import, it reports as a lie about
the game.

Two passes on a cold cache is also now measured rather than assumed. Checksumming
the whole of `.godot/` after each of four consecutive cold passes shows pass 1 → 2
changing one editor bookkeeping file and 2 → 3 → 4 changing nothing. Two is
enough; a third buys nothing.

**Concurrency itself is not the problem and the runner does not refuse it.**
Twenty cold runs of the three turret determinism fixtures and 120 cold
import-and-load runs, under five to seven simultaneous Godot processes, produced
no failures at all. The import cache, the `class_name` global cache and the
Simulation are all genuinely per-process and per-worktree — a long Run's state
hash trajectory is identical across processes, and the `class_name` cache is
complete even after a single pass. What concurrency does is widen the window on
shared state, so the fix is to stop sharing state, not to serialise the agents.
