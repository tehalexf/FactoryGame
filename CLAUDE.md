# DEEP FOUNDRY — working notes

How to build, run and test this project, and the conventions the code follows.
Design lives in [docs/DESIGN.md](docs/DESIGN.md), vocabulary in
[GLOSSARY.md](GLOSSARY.md), architecture rationale in [docs/adr/](docs/adr/).

## Commands

```bash
tools/assets/link_licensed.sh    # point this checkout's assets_licensed/ at the one with the packs
tools/assets/link_licensed.sh --check  # what purchased packs can this checkout actually see?
tools/assets/run_tests.sh        # asset pipeline: licence guard, FBX conversion, Godot import
python3 tools/assets/asset_staleness.py  # is any generated asset older than its recipe?
tools/assets/generate_machines.sh  # regenerate every Machine mesh from its declaration
tools/assets/generate_build_gun.sh # regenerate the Build Gun viewmodel. Committed, unlike the weapons
tools/assets/generate_enemies.sh   # regenerate every Enemy body from its declaration. Committed, like the meshes
tools/assets/convert_weapons.sh  # first-person viewmodels, OUT of the repo; no-op without the packs
tools/assets/convert_props.sh    # set-dressing props, OUT of the repo; no-op without the packs
tools/assets/convert_audio.sh    # hero sound cues, OUT of the repo; no-op without the bundle
tools/visual/shot.sh out.png eye # screenshot a working Factory (eye|survey|ground). Needs Xvfb.
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png routing
                                 # the same, through the player's own camera
                                 # (opening|placing|routing|running|delivering|nest; + bare)
SHOT_SCRIPT=tools/visual/compose_swing_shot.gd tools/visual/shot.sh out.png
                                 # a strip, one frame per tick, of the weapon in frame mid-swing
SHOT_SCRIPT=tools/visual/compose_tool_shot.gd tools/visual/shot.sh out.png "tool bare"
                                 # what is in the player's hands (tool|draw|compare; + bare).
                                 # `compare` may NOT be committed: it renders the purchased arms
tools/visual/frame_cost.sh       # what the yard costs, with a full Factory and a Wave
ENEMY_COUNT=200 tools/visual/frame_cost.sh   # the same, with a Wave big enough to be a scale claim
ENEMY_COUNT=2000 godot --headless --path . --script res://tools/visual/enemy_tick_cost.gd
                                 # what a Simulation *tick* costs with a crowd on it. The other
                                 # half of frame_cost.sh, which times the renderer
SHOT_SCRIPT=tools/visual/compose_wave_shot.gd tools/visual/shot.sh out.png "pair bare"
                                 # a Wave arriving (swarm|pair|triage|boss|distance|crush|wounded;
                                 # + hud, + bare, + near). `wounded` has been shot at (#70)
SHOT_SCRIPT=tools/visual/compose_branch_shot.gd tools/visual/shot.sh out.png bare
                                 # a line that branches, one side blocked (+ bare)
SHOT_SCRIPT=tools/visual/compose_mark_shot.gd tools/visual/shot.sh out.png bare
                                 # the marks a starved Machine wears, over bodies of three heights (+ bare)
SHOT_SCRIPT=tools/visual/compose_dock_shot.gd tools/visual/shot.sh out.png bare
                                 # two Belts that will not dock, for the two different reasons (+ bare)
SHOT_SCRIPT=tools/visual/compose_line_shot.gd tools/visual/shot.sh out.png "eye bare"
                                 # a line that has just started working (eye|survey; + before, + bare)
SHOT_SCRIPT=tools/visual/compose_gunfire_shot.gd tools/visual/shot.sh out.png "turret bare"
                                 # a round actually being fired (turret|hit; + hud, + bare, + plain).
                                 # `hit` is through the player's own camera; `plain` hides the
                                 # purchased arms, which a committed image must do
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
pinned a static build in `.github/ci/toolchain.env`; `wav_to_cue.FFMPEG_MINIMUM_MAJOR` then
makes it a property of the **tool** rather than of CI, because a requirement that
lives only in a workflow file is one a developer runs straight past. The cutter now
refuses a 6.x by name on every invocation, and a build with no release number — a
nightly — is allowed through as "cannot tell" rather than guessed at.

**And a dated autobuild is not a pin, which cost every branch a red CI at once.**
The ffmpeg pin named `autobuild-2026-09-23-14-55`, chosen over `latest` on the correct
argument that a moving pointer is not a pin — and BtbN **prunes** dated autobuilds,
keeping the last fortnight of dailies and the last build of each month. The tag stopped
existing, the fetch 404'd, the toolchain job failed, and because every suite is
`needs:` that job, all three were **skipped** and the single `all suites green` check
reported "a suite did not pass" on branches whose suites were green locally. So the
failure named nothing that was wrong with any tree, and it fired on every push until the
pin was fixed rather than on the one that broke it.

`FFMPEG_CANDIDATES` is the fix and the shape is the lesson: **a list of month-end
artifacts, newest first, each carrying its own checksum** — they are different builds
rather than mirrors of one, so the checksum travels with the URL. The installer takes
the first that answers and says in the log when it has fallen through. The fallback was
**seen to fire** rather than assumed, by pointing the head of the list at a tag that
never existed: it reports `that candidate is gone; trying an older month-end build` and
installs the next. A fallback nobody has watched work is indistinguishable from one that
cannot. Refresh the head of the list whenever you are in that file anyway; an entry
whose month has passed out of BtbN's retention is a silent half of a two-entry list.

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

The Build Gun's viewmodel is scripted output too, and it is the only thing a
player *holds* that this repository may carry: `tools/assets/build_gun_recipe.py`
declares the geometry and the takes and `generate_build_gun.sh` produces
`assets/gear/build_gun.glb`. Every weapon frame is converted out of a purchased
pack instead and is gitignored — see "The Build Gun is the one thing in a
player's hands this project made" and
[docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md) section 7a.

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

### The animation is in a texture, and the bodies are generated

**Two tickets own this section and they are about different halves, which is the thing to
hold on to while reading it.** #38 built the *mechanism* and none of it changed; #79 replaced
the *asset* it was pointed at. Everything below about the bake, the pose texture, the
normalisation and the per-kind MultiMesh is #38's and is current. Everything about which
character a kind wears is history — see "The bodies are declared, not cast", below.

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
  thousand texels, and it does not grow by one texel if the mesh triples. (Those are the
  **cast's** figures, which is the comparison the decision was made against. The generated
  bodies are 19 bones a kind over 104 frames, so #79
  made the texture smaller rather than larger — the budget was a constraint on the
  declaration and `test_generated_enemies` holds it there.) The price is that
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
  exactly the transform the body is placed with — and since #79 the *offset itself* comes out
  of the mesh too, as a marker node the declaration derives from the abdomen's own numbers.
  See "The bodies are declared, not cast", below.

**What reads at thirty metres, and the one thing that did not.** #38 measured rather than
hoped, and the answer was split: a Siege Hulk was unmistakable at any range and a swarm read
as a crowd of bodies rather than a row of boxes — but **a Crawler and a Breaker were the same
dark silhouette** past about twelve metres, because they were the same KayKit rig at the same
declared height and what separated them was armour detail that distance takes first. The
mitigation was to have been the characters' own glowing eyes, and it rendered nothing.

**#49 closed it with size, and the lever is a number in the Simulation.**
`enemy.breaker_hit_height_metres` is 2.2 m against a Crawler's 1.6 and a Siege Hulk's 3.2 —
its own hit volume at last, the arrangement the boss has had since #16 — so a Breaker looms
over the 1.5 m Smelter it is eating and breaks the skyline a Crawler walks under. Because
`WorldView` scales a body by `query_enemy_hit_height_metres`, **the Breaker a player sees and
the Breaker a player shoots at are one thing**; the radius moved with the height for that
reason, since the drawn body is scaled uniformly and a capsule that kept the Crawler's width
would be narrower than what is on screen. Its one balance consequence is that a Breaker bites
from 0.2 m further out, because reach is measured from the hull. **#79 did not touch any of
those six numbers**, and could not have without moving what a player shoots at.

**The claim is a test rather than a sentence, and that is the durable half of #49.**
`tests/cases/test_enemy_silhouette.gd` is `machine_silhouette.py`'s gate pointed at Enemies —
it rasterises each kind's *posed, scaled* outline into an occupancy grid and fails if any two
kinds converge below 0.50. Enemies had no such check, which is exactly how a false claim about
glowing eyes sat in the docs unnoticed. The grid is rasterised at **one cell per player pixel
at thirty metres**, which is what makes it ungameable: detail finer than a cell is detail a
player at that range cannot see either. On the cast the three pairs went 0.42 before #49 and
0.58, 0.83 and 0.67 after it; what they are now is under "The bodies are declared, not cast".

**The glow wiring is gone rather than kept, and the note outlived the asset.** The plumbing
was never at fault and #49 checked rather than assumed it — the baked mesh really did carry a
surface named `Glow`, the branch really did fire, and the same emission on the body rendered a
glowing skeleton with full bloom. The geometry was simply inside the skull. #38 had left the
branch against a future character with exposed glow geometry; that is an untested claim about
art nobody has, and an untested claim in a comment is what produced the ticket. Both
workarounds stayed refused for #38's reasons: moving an artist's vertices is the renderer
editing the model, and `depth_test_disabled` would draw a Crawler's eyes through a wall. **The
generalisation is what survives the cast**: emission is not the answer to two kinds reading
alike, and gross form is.

### The bodies are declared, not cast

**#79, and the user's own words: *"can we not do skeletons…? have an agent use blender
headless and make helldivers 2-esque bugs (not too detailed)"*.** #38 cast three KayKit CC0
characters because they existed and shared a rig, #49 made them tellable apart by size, and
#75 graded their atlas into the palette and gave them metal and grime. Every one of those was
the right move for the asset it had. The asset was still a fantasy skeleton whose skull is a third
of its own height, and #75's closing note had already said so without acting on it.

So the three kinds joined the Machine meshes and the Build Gun: **declared, generated,
committed.** `tools/assets/enemy_recipe.py` holds the geometry and the gaits,
`tools/assets/generate_enemies.sh` drives Blender headless, and
`assets/characters/insects/*.glb` is in git — so a clone with no purchased packs holds the
real thing, and what a player shoots at is this project's own work rather than somebody
else's art direction. **Change a proportion by editing the declaration and re-running, never
by editing a `.glb`**, which is the rule every Machine mesh already obeys and which
`test_generated_enemies.RegeneratingFromTheDeclaration` is the proof of rather than the hope.

#### One builder, three kinds, and what actually separates them

`enemy_recipe.py` is one `Insect` dataclass per kind and **one builder for all three**, which
is load-bearing rather than a saving: an insect is a thorax, an abdomen, a head, mandibles and
some legs, so the difference between a Crawler and a Siege Hulk is *numbers* — which means the
silhouette gate is measuring a declaration a person can edit instead of three separate piles of
geometry. Everything is in **body heights**, because the bake normalises to one metre and
`WorldView` scales by the Simulation's figure; a declaration in metres would be in units
nothing uses.

**Three insects are far more alike than a skeleton, a knight and a golem**, which is the real
risk the ticket named, so they are separated by gross form and never by detail:

| | legs | body slung at | the mass is | carapace |
|---|---|---|---|---|
| Crawler | 6 | 0.30 | spread down a long low body | none — bare chitin |
| Breaker | 6 | 0.50 | a shield at the front, head carried low | 0.96, the tallest thing on it |
| Siege Hulk | 6 | 0.58 | a raised tail at the back | 0.94 |

**All three walk on six since #79's second look**, and the leg *count* is deliberately no
longer one of the separators: four legs under a body carried high is a quadruped silhouette,
and at thirty metres a Breaker read as a horse. What separates them is the body — a long low
narrow wedge against a wide plate carried high against a hull slung over a raised tail — which
is the thing that should be separating them.

#### The rig fits inside #38's bake, and that was a constraint rather than an outcome

- **19 bones a body, every kind, against the cast's 23.**
  Two segments a leg and no more, because six legs at three would be 25 bones of leg alone —
  and because two is what an insect looks like at the only range this matters at.
- **One influence a vertex, at weight 1.** `EnemyBodies.INFLUENCES` keeps the four heaviest, so
  a fifth would be dropped in silence; there is nothing to drop, because a chitin plate is
  **rigid**. Not a shortcut: a smooth-skinned insect leg is a rubber tube, and plates sliding
  over one another at the joint is what an exoskeleton is.
- **Four clips inside each body's own `.glb`**, so a recipe's `libraries` names the character
  itself. The cast resolved against shared-rig libraries, which is the right arrangement for a
  pack of thirteen characters on one rig and the wrong one for three different rigs — a library
  between them could only carry the bones they have in common, which is the root.
- **The gait is a function of phase rather than eight keyframes**, sampled on every frame with
  linear interpolation. Eight keys are eight numbers somebody editing a leg length would have to
  re-derive; a function follows the declaration for free, and what Godot imports is what the
  declaration says rather than what a Bezier handle did to it.
- **A tripod gait is most of what makes these read as insects**, and `tripod_phase` takes the
  pair index *and the side* for that reason. From the pair alone both sides step in unison,
  which is a pace and reads as a pantomime horse — the first version did exactly that.
- **One of #38's tests now passes trivially, and that is worth saying rather than hiding.**
  `test_a_clip_never_walks_the_body_away_from_where_the_simulation_put_it` exists because a
  forward-travelling walk cycle baked as authored would slide a Crawler out of its own
  instance transform, so `_pose` replaces the root's horizontal translation with its rest on
  every frame. A declared gait **authors no root translation at all** — the legs move and the
  body does not — so there is nothing left for that rule to undo and the test asserts a
  property of the declaration rather than of the bake. The rule stays, because the bake is
  what would have to survive somebody authoring a travelling cycle, and because a kind with
  no body still falls back through it.

**The casting itself is unchanged in the one way that matters.** A Crawler *runs* and the other
two *walk*, which was #38's decision and was never about the art: Chaff has to read as
numerous and coming, and a Breaker marches the Nest's own lane under fire (#34). What is gone
are #38's two named stand-ins — `Rig_Large` carried no attack take at all, so a Siege Hulk's
stomp played `Hit_A`, a lurch rather than a swing. A declared body declares its own.

#### What the gate says, and it is the one number that got better on its own

`tests/cases/test_enemy_silhouette.gd` was **not touched** — the threshold is still 0.50, and a
gate rewritten to admit what it is measuring is not a gate. Measured on the generated bodies,
posed and scaled exactly as `WorldView` draws them:

| pair | the cast (#49) | first pass | **shipped** |
|---|---|---|---|
| Crawler vs Breaker | 0.58 | 0.655 | **0.538** |
| Crawler vs Siege Hulk | 0.83 | 0.989 | **0.878** |
| Breaker vs Siege Hulk | 0.67 | 0.868 | **0.794** |

**Every pair is further apart than the cast managed**, which is the declaration working rather
than luck: the cast was three humanoids of the same proportions at three heights, so #49 could
only separate them by size, and that walked the Breaker toward the boss as fast as it walked it
away from the Crawler. A body slung at 0.30 against 0.50 against 0.58, a bare back against a
plate at 0.96, and mass spread down a long tail against massed in a front shield are
independent differences, so the pairs no longer trade against one another.

> ### ⚠️ The Crawler-against-Breaker pair has about four hundredths of headroom
>
> **0.538 against a 0.50 floor.** If you are about to move a Crawler or a Breaker proportion —
> a width, a depth, a sling height, a tail length — that is your whole budget, and
> `test_enemy_silhouette` is what will tell you. **Re-measure after
> `godot --headless --path . --import`**, for the reason two paragraphs down, and read "leg
> thinning is free against this gate and body bulk is not" before you pick which number to
> move.

**The third column is #79's second look and it cost real margin — 0.655 to 0.538 on the
binding pair — which is reported rather than hidden.** The Breaker went from four legs to six,
because four under a body carried high is a *quadruped* silhouette and at `triage`'s thirty
metres it read as a horse; six legs splayed low is the cue that says insect at range. Leg count
was carrying 0.12 of that separation and is now carrying none of it, so the body is carrying all
of it. The gate was **not touched** — the threshold is still 0.50, and a gate rewritten to admit
what it is measuring is not a gate.

**Six legs were kept at 0.538 over four at 0.655 deliberately, and the rule is #68's own.**
*Separation is a floor to clear, not a quantity to maximise* — that ticket measured a saturated
green at ΔE 73 and threw it away, because clearing the floor was the whole requirement and the
rest was a neon slab in a dark palette. The same trade is here in geometry: the four-legged
Breaker buys 0.12 of margin **on the instrument** at the cost of the thing the instrument exists
to serve, because the gate rasterises an outline and cannot see that the outline is a *horse*.
When a gate and the judgement it stands in for disagree, the gate is the thing that is wrong
about the world — and the right response is to spend its margin, not to protect it.

**And the re-tune had to be driven back and forth across that floor to land, which is worth
knowing before somebody repeats it.** Bodies widened and legs shrunk to kill the fence took the
pair to **0.385**, *below* the floor, because a fat Crawler is a small Breaker. What bought it
back was pushing the two the opposite ways at once — the Crawler longer, lower and narrower
(0.44 wide, slung at 0.30, an 0.88 tail) and the Breaker wider and higher (0.88 wide, slung at
0.50, a 1.02 plate at 0.96). **Leg thinning is free against this gate and body bulk is not.**

The Crawler against the Siege Hulk at 0.878 is nearly disjoint, which is the expected answer
rather than a suspicious one: a 1.6 m body slung low and a 3.2 m one slung high share almost no
cell of a grid rasterised at one cell per player pixel at thirty metres.

**⚠️ Every one of these numbers must be taken after `godot --headless --path . --import`, and
three readings in this ticket were taken without it and were lies.** The measurement loads the
`.glb` through `res://`, so it gets whatever the **import cache** holds — and regenerating a
body does not refresh that. Three separate geometry changes reported *byte-identical*
separations, which is how it was caught: a figure that does not move when the mesh does is the
symptom. `tools/run_tests.sh` runs `--import` on every invocation for exactly this reason, so
the suite is safe; a one-off script is not. It is the `.pyc` trap below in a second costume —
**a generated asset has two caches between the declaration and the answer, and both will lie
quietly.**

#### The legs were the subject and the body was the background, and a render is the only thing that said so

**#79's second look, and it is #41's rule arriving from a direction this file had not met: a
mark can be in the right place, the right colour and the right size and still be wrong because
it is *bigger than the thing it is attached to*.** The first pass put a Crawler's knee at 0.95
against a back at 0.59 — so the leg arc was the top of the silhouette, the normalisation
measured *it*, and the body was a small lump inside a cage. At the `pair` camera's six to twelve
metres a rank of them read as a **picket fence with no bodies behind it**, which is a worse
failure than the one it was solving: the thing a player has to shoot had gone missing.

Three changes, and the order they had to be made in is the finding:

- **The knee comes down to just over the back.** Measured on the shipped bodies, a Crawler's
  legs top out 0.161 of its height above its back against the first pass's 0.36 — so the arch
  is still there, which is what reads as splayed rather than as a quadruped, and it is no
  longer the subject. **The Breaker and the Siege Hulk are now crowned by their own bodies
  instead** (−0.337 and −0.122), which is a separator in its own right and falls out of the
  carapace rather than being tuned for: the kind a player ignores is the one whose legs you
  see first, and the two that matter are a plate and a hull.
- **The legs are blades and are much thinner.** `Leg.blade` is #79's one new field: a square
  section is the same width from every angle, so a leg thin enough not to be the mass is a thin
  dark rod from *every* angle too, which is the "flat planes" half of the complaint. 1.6 deep in
  the plane it swings through against its across-swing width gives it a lit face and a shaded
  one. Thickness went from 0.075 of a body to 0.038 on the Crawler at the same time, and
  **that** is what took the fence away rather than the cross-section.
- **The body got the room the legs gave up**, and then had to give some of it back. See the
  gate section above: widening both bodies took the Crawler-against-Breaker pair *below the
  floor*, and what landed was pushing the two opposite ways rather than both outward.

**And the Breaker's legs are `Soot` rather than `CastIron`, which is a one-line content change
that a render forced.** Every surface of a kind takes that kind's single roughness, and the
Breaker's is `WeldedSteel`'s 0.45 — so at metallic 1 under this project's bright ochre sky its
*legs*, of the identical material a Crawler's dark legs are made of, came back as **pale planks
brighter than the carapace they hang from**. A limb that is the brightest thing on a body reads
before the body does. It costs no silhouette, because a material cannot move an outline.

**What the pair of renders settles**, and both are committed: a Breaker that was a pile of white
planks is a heavy plated mass on thin dark limbs, and a Crawler rank that was a fence is a row of
low dark bodies with an oxide tail. **What it does not settle** is the honest limit already
recorded below — these are chamfered boxes, and whether that reads as *this game's* bug or as a
Machine with legs is a judgement for somebody with a mouse.

#### The weak point is in the mesh now, which closes the one disagreement it could have

A Siege Hulk's vent is the only place in this project where geometry carries a rule. It used
to be placed by two constants in `world_view.gd` while the body it is an opening in was
somebody else's art, so editing one could not move the other and **nothing would have said
so**. `enemy_recipe` derives the tail's far face from the abdomen's own declaration,
`generate_enemies` exports it as a marker node — carrying no mesh, so it falls out of
`_flatten` by itself exactly as a Machine's `Port_*` marker does — `EnemyBodies.Body.vent_offset`
reads it back through the same normalisation the bone matrices get, and `WorldView` builds the
grille there. Editing `abdomen_rise` moves the glow with the tail.

**An insect abdomen is a better home for it than a golem's back was.** The tail cocks *up and
away* from the body, so the vent lands at (0, 0.84, -0.85) in body heights against the golem's
(0, 0.50, -0.30): it is the one part of the silhouette a player cannot mistake for armour and
the one part they can only see from behind. The constants remain as the fallback for a kind
drawn through the procedural hull, which is what they were measured against, and
`test_only_the_boss_declares_a_weak_point_and_it_is_behind_and_above_it` asserts the body's
answer **differs** from them — because a declaration that happened to land on the old pair
would leave the test unable to tell the mesh's answer from the renderer's.

### What an Enemy is painted with, and why neither a tint nor a grade is the answer any more

**Three tickets answered this and only the third stops being a repaint.** #38 drew the pack's
one 1024-square swatch atlas — flat cells with a vertical gradient, a whole thigh samples one
of them — through a dark multiply per kind. #75 is the user looking at that: *"the enemies look
like shit honestly"*. They were right, and the reason is arithmetic rather than taste.

**A multiply cannot change a ratio.** Measured off the committed atlas by sampling
`Skeleton_Minion`'s own UVs, which was the only honest way to ask what a Crawler was wearing:

| what | cell | linear albedo |
|---|---|---|
| skull, limbs | (174, 200, 212), a cold blue-white | **0.551** |
| ribs, pelvis | (161, 95, 72), a warm red-brown | 0.162 |
| boots | (83, 71, 65) | **0.067** |

Eight to one between the skull and the boot, and one tint scales both by the same number — so
whatever the tint was, a Crawler was a bright skull with a dark smudge under it, and turning it
down only moved the whole thing toward black. Measured off the `swarm bare` render that opened
#75, the median Enemy pixel came to a linear luminance of **0.009 against a ground at 0.046**,
a fifth of the thing it was standing on. #75's answer was `enemy_grade.py`, which remapped the
*atlas* onto the palette's ramps and closed the ratio from 8.2:1 to 3.6:1.

**#79 does not need a grade, because a part is assigned its palette entry rather than having
one inferred from a pixel.** There is no ratio left to fight: a Crawler's carapace is
`OxideRed` because somebody wrote that down. So the surface is resolved by **the name of the
surface** — the declaration names an entry per part, the generator emits one glTF primitive a
material, `EnemyBodies._flatten` names each surface after it, and `WorldView._skinned_mesh`
loads `assets/machines/materials/<name>.tres`, which is the very `StandardMaterial3D` the
Walls, every Machine body and #73's cargo already draw. One declaration, four runtimes.

| Kind | carapace / plate | abdomen | joints and legs | mandibles |
|---|---|---|---|---|
| Crawler | — | `OxideRed` | `Soot` | `DullBrass` |
| Breaker | `WeldedSteel` | `CastIron` | `Soot` | `DullBrass` |
| Siege Hulk | `CastIron` | `OxideRed` | `Soot` | `DullBrass` |

**`tools/assets/enemy_grade.py` is deleted rather than left unread**, along with the six KayKit
characters, their four animation libraries, the intake FBX, the atlas copies and the bone map —
14 MB and 55 tracked files. A generator whose output nothing samples is `prop_grade.py`'s own
opening defect and the rule `Definitions` applies to a tuning key nothing reads.

**The UVs are worth sampling now, which they were not before.** The cast's unwrap pointed every
limb at one cell of a swatch sheet, and the shader's own note said a normal map through them
would be a flat colour. A generated body is box-projected at one UV unit to the authored metre,
which is one unit to the *body height* — so the palette's real tiling map repeats across it, and
how finely is one uniform, `uv_scale`, written as a fraction of a body for `grime_metres`' reason.

**The per-kind tint survives and has lost its last job but one.** Before #75 it carried the
whole level; #75 left it carrying a cast; #79 takes the hue as well, because the declaration
assigns it. What is left is near white and says only *which kind* — warm for the Crawler, cold
for the Breaker, neutral for the boss — which is the readability cue #49's sizing was carrying
alone.

#### Chitin is a glossy dielectric, and two renders rejected it anyway

**#79's ticket asked for #75's `metallic = 1` to be re-derived and measured rather than
inherited, and it was — by shipping the other answer into a render and looking at it.** The
ticket's reasoning is fair and its physics is right: #75's figure was defended as *a dielectric
at 0.17 albedo has nothing to reflect under a sky dome*, that premise is about the pack's
graded atlas rather than about a declared body, and a plated insect shell really is a glossy
dielectric with a bright specular of its own.

**The picture says no.** At `metallic = 0` and roughness 0.45 a Crawler came back as pale tan
limbs with a white speckle crawling over them and the Breaker's legs as chrome. The reason is
the palette rather than the biology: it runs **0.055 to 0.14 albedo**, and `_sync_scenery`
takes ambient *and* reflections off a bright ochre sky precisely because the generated
surfaces are metal. A dielectric at that albedo under that sky is a body whose own colour is a
twentieth of the specular sitting on top of it — so what a player sees is the sky with a
silhouette cut out of it, which is #75's own sentence about a rough-plastic highlight arriving
from the opposite direction.

So the Enemies are metal, at the palette's own figures: `WeldedSteel`'s 0.45 for the Breaker,
`CastIron`'s 0.62 for the boss, and 0.55 for the Crawler between them. **#75's number survives
its own argument being superseded**, and the durable form is worth more than the number: not
*a dark dielectric has nothing to reflect*, but **this world's light is tuned for metal, so
anything in it that is not metal reads as a smear**. The dielectric is the honest physical
answer and the wrong rendering answer, and that distinction is the whole of what this
sub-section is for.

**And it was tested a second time, on a surface that had been fixed in the meantime**, which
is the right thing to do once the first rejection's evidence turns out to have had another
cause — the white speckle that helped convict the dielectric was `relief` on faceted plate, not
the material. Re-rendered with the relief and the lift corrected, it comes back **chalky**:
pale grey plate with safety-orange abdomens, reading as painted concrete rather than as a
shell. A dielectric's diffuse is flat and carries none of the sky's gradient, and the metal's
reflection is exactly what gives plate its sheen. So metal stands on better evidence than it
did, and the honest summary is that the ticket's physics is right about chitin and wrong about
this renderer.

`test_an_enemy_is_metal_because_the_light_in_this_world_is_tuned_for_metal` therefore survives
a ticket that set out to reverse it, with the reason rewritten and a second clause added —
the pair is asserted together, because a dielectric at any roughness and a metal polished to a
mirror each satisfy one half.

#### What it costs, and "not too detailed" as a number

The user's instruction was *"not too detailed"*, which is a performance instruction as much as
a style one — these are drawn through one MultiMesh a kind in the thousands. Measured with
`ENEMY_COUNT=<n> tools/visual/frame_cost.sh` on the same scenario, the cast against the
declaration:

| | the cast (#38) | declared (#79) |
|---|---|---|
| primitives, 18 Enemies | 4,291,354 | **3,994,066** |
| primitives, 71 Enemies | 5,505,532 | **4,158,192** |
| video memory, 18 / 71 | 265.4 / 265.9 MB | **259.2 / 259.7 MB** |
| `WorldView.sync`, 18 | 16.76 ms | 17.22 ms |
| `WorldView.sync`, 71 | 20.76 ms | 20.25 ms |

**The declaration is cheaper on the figures that are properties of the asset, and the gap
widens with the Wave** — which is the half that matters, because the Wave is what grows. 297,000
fewer primitives at 18 Enemies and **1.35 million fewer at 71, a quarter of the frame's total**,
because 788, 588 and 812 triangles a body replace 4,858 *vertices* apiece. Six megabytes less
texture, because the glTF embeds no image and the palette's maps were already resident for the
Machines. `test_generated_enemies.test_not_too_detailed_is_a_number`
is the ceiling that keeps it so when somebody adds a part.

**The sync figure is not a finding and should not be read as one.** Half a millisecond on a
17 ms rebuild, measured on a machine running five other Godot processes at load 11, is inside
the noise of the instrument — and both columns are far above the figures this file quotes for
#38, because the Factory the harness builds has grown since. What the measurement is for is
the two columns above it, which are counts rather than timings.

**The pose texture went down too**, which is the half #38's architecture actually cares about:
19 bones a kind against the cast's 23, over 104
frames rather than 90. `test_generated_enemies` holds the bone budget at 23 so a later
declaration cannot quietly walk past it.

**And the Simulation's own tick is untouched by construction.** `ENEMY_COUNT=2000
enemy_tick_cost.gd` times `Simulation.step`, and #79 changed no file under `sim/` at all — the
bodies are an asset and the surface is a renderer decision, so a difference there would have
been a bug rather than a cost. Measured at 2000 Enemies on this machine it is about 300 ms a
step either way, which is #76's crush figure inflated by the same contention the sync column
carries; the quiet-machine figure that file quotes is 94 ms and is the one to trust.

**The GPU half is unmeasured, exactly as #38's and #75's were.** `frame_cost.sh` measures the
CPU rebuild, the skinning is in a vertex shader, and Xvfb is llvmpipe. The levers if it ever
bites are the same two: `relief_fade_end`, and dropping the grime field's second octave.

#### Four things a second look found, and only one of them was what it looked like

**The first pass measured a histogram and shipped a broken surface**, which is this file's own
lesson arriving again: the medians were defensible and the Breakers were blue-and-white
confetti. Four faults, and the order they were *found* in is not the order they were guessed
in — each was isolated by rendering one probe.

1. **It was `relief`, not the roughness spread.** The obvious suspect is #75's per-fragment
   roughness, because a metal's reflection *is* its surface. Probed at `roughness_spread = 0`
   and **the confetti was unchanged**; probed at `relief = 0` and it vanished completely. The
   mechanism is the derived normal: on #75's smooth skinned characters the base normal already
   varies across a face, so bending it a little bends it a little, where a generated body is
   **flat-shaded faceted plate** whose facet normal is constant — so the field is the *only*
   variation on that facet, and on a metal it swings the reflected direction across a sky that
   is bright ochre at the horizon and dark blue at the zenith. Hence blue and white. `#79`
   ships 0.003, a quarter of #75's 0.012, bracketed at 0, 0.003 and 0.012 by looking.
2. **The lift was applied in the wrong space and was clipping past a physical albedo.** It
   multiplied the palette entry's **sRGB** colour and handed the product to a `source_color`
   uniform, and that conversion is a 2.4 power — so 1.6 on `CastIron`'s 0.52 became
   `srgb_to_linear(0.83) = 0.66` against the 0.23 a Machine gets, an effective **2.9x**. On the
   Breaker's cold cast it took `WeldedSteel` to a **linear albedo of 1.13 in blue**: over one,
   a surface returning more light than it receives. It is applied in linear now and clamped at
   `ALBEDO_CEILING = 0.80`, and bracketed at 1.0 / 1.8 / 2.6 — 1.8 reaches `triage` parity with
   the cast and 2.6 adds 0.002, so 1.8.
3. **The dielectric was re-tested on the fixed surface and is still wrong, for a new reason.**
   That was the right thing to check: with the speckle traced to `relief` rather than to the
   material, the first rejection might have been convicting the wrong thing. Rendered at
   `metallic = 0` with the relief and the lift corrected, the bodies come back **chalky** —
   pale grey plate with safety-orange abdomens, reading as painted concrete. A dielectric's
   diffuse is flat, so it carries none of the sky's gradient; the metal's reflection is what
   gives plate its sheen. Metal stands, and now for a better reason than "the dielectric was
   speckled".
4. **The texture density is fine, and that was measured rather than argued.** Texels per real
   metre, #65's own figure: **Crawler 1455, Breaker 1058, Siege Hulk 727, against a Machine's
   931**. So the Crawler is 1.56x a Machine and the boss is *below* one — not the order of
   magnitude it was suspected of, and `filter_linear_mipmap` handles the minification anyway.
   What has no mip chain is the **procedural** field, which is why (1) was the fault and this
   was not.

**And a structural fix that (1) uncovered.** `relief` fades over 14-34 m because a procedural
field past the range where one feature is under a pixel stops being detail and becomes noise.
`grime_depth` and `roughness_spread` are the same field and **did not fade** — #75 computed
`near` and applied it to one of the three. Both fade now, which is #75's own argument finished
rather than a new idea.

#### What the measurement says, and the two frames where it says the wrong thing

#75's method: linear luminance over the pixels the change moved, against the ground in the
same picture.

| frame | before, median | after, median | ground | after / ground |
|---|---|---|---|---|
| `triage` — thirty metres, the readability shot | 0.091 | **0.078** | 0.049 | **1.61x** |
| `boss` | 0.049 | **0.051** | 0.046 | 1.11x |
| `pair` — six to twelve metres | 0.074 | 0.031 | 0.052 | 0.58x |
| `crush` — from above, in the Nest's shadow | 0.021 | 0.014 | 0.042 | 0.33x |
| `swarm` — six metres, **into the sun** | 0.058 | **0.004** | 0.046 | **0.09x** |

**At the two vantages that decide whether a Wave is readable the bodies are at parity with the
cast** — `triage` at 1.61 times the ground where #75 left an Enemy at 0.46 times, and `boss`
fractionally *above* the cast. Re-measured after #79's geometry second look and they moved by
hundredths, which is the expected answer rather than a lucky one: that pass changed proportions
and a leg count and touched no material, and these are a property of the surface.

**`swarm` and `crush` are still below the ground and that is said plainly rather than
defended.** `swarm` is a *ninth* of the floor, which is worse than the fifth #75 called "not a
dark Enemy, it is a hole in the floor". Both are the cases where the body is between the camera
and the light or inside the Nest's shadow, and **neither is a lift problem**: bracketed at 1.0,
1.8 and 2.6, `swarm`'s median moved 0.000 → 0.0041 → 0.0042 and then stopped, because a backlit
metal in shadow has almost nothing to return whatever its albedo says. Buying it with more lift
was offered and refused.

**Part of `swarm`'s figure is the mask rather than the bodies, and that is the sixth time this
file has paid for a vantage — the first time as a *measurement* rather than as a missing
subject.** The preset stands at about forty-five metres looking down a lane at bodies a few
pixels wide, so most of the pixels #75's method selects are **edge** pixels; and an edge pixel
on a thin dark leg against bright ground is mostly ground, which drags a median toward the
ground's value from below rather than reporting what a body returns. Every other instance of
this hazard has been a camera that could not see its subject (#48's split marks, #49's `triage`,
#52's survey ore, #56's dock posts, #76's `crush`, #79's own `wounded`). This one frames the
subject correctly and is a bad *instrument* at that range.

**It is not only the mask, and #79's second look is the evidence.** That pass halved every leg's
thickness and enlarged every body — which changes the edge fraction of the `swarm` mask
materially and in the direction that should have made an edge artefact *worse* — and the median
came back at **0.0041 against 0.0041**, unmoved to the fourth decimal. So whatever dominates
that number is not leg width, which is what an edge-pixel artefact would be most sensitive to.
**Read it as a real loss with a measurement artefact on top of it, and not as either one
alone.**

What it actually wants is either a fill light reaching the Enemies or an emissive cue on a kind
— and the second is newly *possible* rather than merely proposed, because #75 refused
`depth_test_disabled` for its own reasons and found the KayKit eye geometry was inside the
skull, so a generated body is the first thing in this project that could place one. Both are
their own ticket. A `swarm` figure that is honest about the bodies wants a vantage nearer than
forty-five metres, which is a third thing and is a change to the preset rather than to the game.

#### What the pictures settle, and what they do not

Six pairs are committed, `bare` throughout because the yard is drawn out of the purchased packs
and this repository is public:

```bash
SHOT_SCRIPT=tools/visual/compose_wave_shot.gd tools/visual/shot.sh out.png "<preset> bare"
```

`docs/images/enemies_insect_{swarm,pair,triage,boss,crush}_{before,after}.png`, plus
`enemies_insect_wounded_before.png`.

- **`triage` is the one that carries the ticket**, because thirty metres is where a player
  decides what a Wave is. Before: three humanoid silhouettes in three sizes, the Crawler and the
  Breaker separated by height alone. After: a line of low six-legged bodies with oxide tails
  against the iron of their own thorax and legs, and a wide plated thing standing over
  them. The oxide tail is a second cue beside height, which is the thing #49 recorded as missing
  and #75 could not buy with a tint.
- **`crush` answers #76's question for the new bodies**, and it answers it better than the cast
  did: eight insects pressed into the Nest's corner read as eight bodies with legs interleaved,
  where eight skeletons read as a heap. Legs splayed wide is a silhouette that *shows* a crowd.
- **`swarm` is the honest loss.** Six metres, into the sun: the generated bodies are
  silhouettes where the cast was pale. Some of that is a chitin bug doing what a chitin bug
  should do between you and a low sun, and some of it is a real step backwards; the measurement
  above says which frames it costs and the lever is `ENEMY_LIFT`.
- **`wounded`'s after is committed and it is a bad picture, which is worth recording.** That
  preset frames the spot where the last Enemy died, and the composer drives the kill by aiming
  the player at a target read back out of the queries — so where the camera ends up is a
  function of where the Wave happened to be. On the generated bodies it came to rest about
  forty metres from its subject and the Enemies are a smudge on the horizon. That is the
  vantage hazard this file has now paid for six times (#48's split marks, #49's `triage`,
  #52's survey ore, #56's dock posts, #76's `crush`, and `swarm`'s own luminance above):
  **a composer that frames from what it meant to produce is a composer that cannot see what it
  produced.** `swarm` is the odd one of the six and is worth reading beside this one — its
  camera frames the subject correctly and is still the wrong instrument, because at
  forty-five metres the thing it measures is mostly edges. Nothing here chased it,
  because #70's glowing cracks are drawn by the shader off `INSTANCE_CUSTOM` and #79 did not
  touch that path — so the surface claim is carried by `pair` and `triage`, and re-aiming
  `compose_wave_shot`'s `wounded` camera is a job for whoever next has a reason to look at a
  wound.

**What no still image settles**, and it is the question the whole ticket is really about:
whether a tripod walk reads as an insect walking. Everything measurable is measured —
silhouette separation, luminance, triangles, texels, video memory — and none of it has an
opinion about gait. The levers are the two numbers in `enemy_recipe.leg_pose` (the stance
fraction and the lift) and the clip lengths in `CLIPS`, all in the declaration rather than in
tuning, because the Simulation reads none of them.

**And the bodies are faceted plate rather than organic**, which is the honest limit of this kit.
A Terminid has curved chitin and a lot of it; these have chamfered boxes, because that is what
`machine_parts` is good at and what every other surface in this world is made of.

**That was looked at rather than left as a worry, and the answer splits by range.** At thirty
metres it works and is the read the ticket was for: a low dark line with a taller plated thing
standing over it. At the `pair` camera's six to twelve metres it does not — the Breaker is a
boxy mass on thin legs and the Crawler's abdomen is a saturated orange block, and the whole
reads as **a machine with legs rather than as a bug**. That is a real gap and it is recorded as
one; it was not grounds to hold the branch, because the geometry is separated, the frame is a
quarter cheaper, the surface is fixed, the licence position is strictly better than a CC0 cast,
and it is emphatically not a skeleton — and a long-lived art branch against three other agents
in `world_view.gd` costs more than it buys.

**The shape the renders suggest, for whoever picks the close range up**: a *segmented* body —
thorax and abdomen as two masses with a narrow waist between them rather than one run of boxes —
**arched** legs rather than straight ones, and a front feature where a head would be. And the
orange abdomen wants measuring: at `pair` it is the brightest thing in frame, which is adjacent
to #80's finding about the Nest and may share a cause.

#### Five things about the shader, three of them carried over from the ground

**All five are #75's and all five are current**, because every one of them is about a
surface rather than about where the albedo came from. #79 changed one thing in this file:
`uv_scale`, which the cast's swatch UVs could not have used.

- **It is sampled in the rest pose, not in world space.** The yard's noise is a function of
  where you are standing because the yard does not move; an Enemy does, and a world-space read
  makes the grime swim over a walking Crawler like a projector. The rest position is the one
  coordinate fixed to the body and it costs one varying — it is the pre-skin `VERTEX`, which
  this shader already has in hand. It is in the normalised units `EnemyBodies` bakes a body
  into, so `grime_metres` is a *fraction of a body* and the same number gives a 3.2 m Siege
  Hulk coarser pitting than a 1.6 m Crawler in absolute terms, which is the right way round.
- **What is visible is the slope, not the height**, and the first render proved it the other
  way about. #42 found that a physically reasoned two centimetres over a metre is a one-degree
  tilt the sun cannot find; here the first numbers were far too *large* and produced a swarm of
  chrome camouflage blobs. Both are the same lesson — the knob is `relief` over `grime_metres`
  — and the useful half of the failure is that it settled the plumbing in one glance, which is
  the question #42 needed two diagnostic renders to answer. `relief` is written as a fraction
  of the Enemy's own height for `bump_height_metres`' reason, so 0.012 on a 1.6 m Crawler is
  two centimetres of pitting over three-centimetre features. A generated body is faceted
  plate with chamfered edges rather than a smooth cast, so the field now reads **over** a
  silhouette that already has structure in it instead of supplying all of it.
- **The gradient is not normalised, and that is what the chrome render was really about.**
  Normalising it turns the knob into "how far to rotate toward the gradient", which tilts
  every fragment by the same amount whatever the field is doing — so a flat patch of the field
  stops being a flat patch of the body. Unnormalised it is an ordinary height-field normal and
  a smooth region stays smooth, which is most of the difference between a casting and a
  camouflage pattern.
- **The relief fades out with distance**, over 14 to 34 m, for `ground.gdshader`'s two reasons:
  a procedural field has no mip chain, so past the range where one feature is under a pixel it
  stops being relief and becomes noise; and a Crawler at forty metres is a silhouette with a
  highlight on it, which is what a player is reading at that range anyway.
- **The roughness is spread either side of the material's own figure by the same field.** A
  surface whose roughness is one number is a surface with one highlight on it, and dirt in a
  crease is matte where a worn edge is polished. That difference is most of what says "metal
  that has been outside" rather than "grey plastic", and it costs nothing — the field is
  already sampled for the albedo.

### An Enemy that takes damage, and a death that leaves something behind

**#70, and the first thing it found is that half of it was already there and did not work.** The
ticket says `query_enemy_health` and `query_enemy_max_health` "have existed since #9 and the
renderer reads **neither**". It reads both: `WorldView._health_fraction` has put the health
fraction on `INSTANCE_CUSTOM.y` since #38 and `enemy_skin.gdshader` has multiplied albedo by
`mix(1.0 - wound_darkening, 1.0, health)` ever since — a correct implementation of the wrong
idea. **A wound cannot be a darkening on a body that is already the darkest thing in frame.**
#75 measured the median Enemy pixel at a linear 0.021 against a ground at 0.046, so taking
another 45% off a dying Crawler moves it from dark-against-dark to darker-against-dark, and at
thirty metres that is a silhouette either way. It is #42's Wall, #52's ore, #64's tool and #65's
gloves a **fifth** time: a value picked against the wrong background — and here the background is
very nearly black.

So **a wound is light rather than the absence of it**, and the vocabulary was already in this
world: a Siege Hulk's vent is an unshaded glow and is the one place geometry carries a rule
(#16). A hurt Enemy is a casting cracked open with something hot inside it.

#### Two free channels, spent exactly as #38 and #75 said they would be

`INSTANCE_CUSTOM` is four floats. `.x` is the animation row and `.y` the health fraction, both
#38's; `.z` and `.w` were written as zero and read by nothing, and #75's closing note named what
they were for almost to the line — *"a mark that has to be in a different place on each one wants
a per-instance offset into that field"*. That is `.z`:

- **`.z` is a wound seed**, the Enemy's own **serial** modulo 97 and spaced well past the field's
  own scale. The grime field is a function of the rest pose alone, so it is identical on every
  body of a kind — right for wear and wrong for a wound, because six Crawlers scorched in the
  same place are six copies of one Crawler. A serial is issued once and never reused (#9), so it
  is a Simulation quantity exactly as the animation row beside it is, and two Runs down the same
  script wear the same marks on the same bodies.
- **`.w` is how fresh the last hit is**, 0 to 1, out of `game/combat_events.gd`. **A health
  fraction is a condition and a round landing is a change**, which is the whole reason the two
  ride different channels and come from different places: an Enemy at 40% looks the same on the
  tick a round lands and on the tick after, and what a player emptying a magazine into a Siege
  Hulk's glacis needs to know is that *this round* connected. Aged by subtracting the event's own
  tick from `query_tick`, so a frame that stepped nothing draws the same flash.

**The stride stays sixteen and nothing widened**, which is what made a free channel the cheap
door: `use_colors` would have taken it to twenty and with it `_write_skinned_instance`,
`_stride_for` and every accessor that divides by one.

#### A death is the one thing no channel can carry

`_remove_enemy` closes the gap on the tick a Crawler dies, so there is no instance left to fade
out and no serial left to resolve. #75 wrote that down and #69 built the answer: a serial that
was in the array last frame and is not in it now, with **where the body was last seen alive**,
which is the one fact nothing else in the project can produce. #70 is the first consumer of
`CombatEvents.Kind.KILLED` and it needed no change to the Simulation at all.

- **Two marks, because they answer different questions.** A burst says *now* and is gone in a
  quarter of a second; a soot stain says *here* and is still on the ground two and a half
  seconds later when a player sweeps back across the lane. Both are sized off
  `query_enemy_hit_height_metres` for the kind that died — the very number the drawn body is
  scaled by — so a Siege Hulk's death is twice a Crawler's, which is #41's rule.
- **`CombatEvents.MEMORY_TICKS` went from 60 to 150**, which is the stain's own life. That
  constant has always meant "as long as the longest-lived mark drawn off one" and was 60 while
  every mark was a flash or a burst.
- **Their own MultiMesh, built on the first sync**, so the scene tree does not grow when
  something dies — `test_a_death_is_never_a_node_and_neither_is_a_wound` asserts zero growth over
  a Breaker being killed, which is `test_an_enemy_is_never_a_node`'s claim pointed at the one
  ticket most likely to break it.

#### Five things the renders threw away

Every one of these was drawn, was the right colour, was in the right place and was wrong.

1. **The burst as a cube read as a crate standing in the Wave.** It began as the unit box #69
   scales a muzzle flash and an impact out of; at a death's size that is a 1.3 m pale box among
   the Crawlers, which is #69's own finding about a 0.75 m impact and #56's about a red post, a
   third time. A **flat disc** cannot read as an object, because nothing in this world is a metre
   across and six centimetres thick — and it needed a cylinder rather than the shared box, since
   at ten metres a flat *square* reads as a plate somebody put there. The third shape was the
   obvious correction to the second and is also wrong: seen from eye level a flat disc on the
   floor is nearly edge-on and reads as a **bar**, so it was given three tenths of a body's
   height to read as a puff — and came back as a pale slab two metres wide standing in front of
   the Chaff and hiding one of them. **A mark on the ground is allowed to look like a mark on
   the ground**; what it may not do is look like something somebody put there.
2. **The stain at three centimetres read as a plinth.** #52's rule for the one mark that lies on
   the floor — paint, not a plinth — and one centimetre is what makes it paint.
3. **Thresholding the wound against 1.0 opened nothing at all.** The arithmetically tidy version
   is "the field, scaled by how hurt you are"; the field does not reach the ends of its own
   range. **Measured**, two octaves of value noise mixed 0.68/0.32 come out at mean 0.497 and
   standard deviation 0.149, with coverage 4% above 0.75 and 1.3% above 0.80 — so a Breaker at
   half health opened **nothing** and the first render of a 50% Breaker is indistinguishable from
   a fresh one. The band is now measured against where the field actually lives, `0.82` at full
   health down to `0.58` at none.
4. **A 0.10 ramp above the threshold spent the whole wound in the ramp.** At half health a body
   reached *full* brightness over half a percent of itself. `wound_edge` is 0.04.
5. **At the grime's own scale a dying Breaker came out as a speckled leopard** — dirt-sized
   detail doing a wound's job, which reads as camouflage rather than as a body that has come
   apart, and is #75's own chrome-camouflage failure one layer up. `wound_metres` is six times
   `grime_metres`: a crack is the size of a limb segment.

#### What the pictures and the pixels say

[`docs/images/enemy_damage_before.png`](docs/images/enemy_damage_before.png) against
[`_after`](docs/images/enemy_damage_after.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_wave_shot.gd tools/visual/shot.sh out.png "wounded bare"
```

Both frames are the same Run at the same tick: a Breaker at **90 of its 240** hit points standing
beside one on full health, and the spot a Crawler fell on six ticks earlier. Before: the two
Breakers are the same dark body, and the only thing where the Crawler was is **#69's impact
burst** — which is a mark about the *round* and looks identical whether the thing it hit lived or
died. After: the hurt Breaker wears glowing cracks across its lower body and there is a disc of
fire and a scorch on the ground where the Crawler was.

Measured over the two Breakers' own pixels in the committed after frame, counting hot glow
(R > 190 and R − B > 110): **18 pixels on the hurt one against 0 on the fresh one**, where the
two stand side by side and are otherwise the same body. (The pair was re-rendered on the merged
tip, because #76's separation pass changed where a Wave stands; the figures before that merge
were 41 against 3 on a frame where the hurt Breaker was nearer the camera. The *ratio* is the
claim and it survived.) That is the acceptance criterion as a number rather than as an
impression, and it is the right *kind* of difference — bright warm specks on a dark body, where the atlas's own `OxideRed` chest is dull
and dark and cannot be confused with it.

**`wounded` is #70's preset and it exists because no other one can see the question** — the
name is not `crush`, which #76 took in the same hour for the crowd pressed against the Nest —: every other
preset renders a Wave that has never been shot at, and the Factory a composer builds has no
Ammunition chain, so its Turret is dry from the first frame to the last. The player is the only
gun on the Map that can be made to go off, so the shot is driven the way `test_world_view`'s
rifleman fixture is — aim by sending the pixels that close the bearing, fire, and read the result
back out of the queries. Four things it cost, every one of them found by a wrong picture:

- **A `LOOK` intent carries fixed-point pixels.** The first version sent 990 and turned the player
  by nothing at all.
- **A round aimed at a Breaker's middle hits the Crawler in front of it, every time.** A Wave
  trickles out of one Breach and stands in a heap, so twenty-four rounds went into Chaff and left
  both Breakers untouched. The aim is lifted to 1.15 of the target's height — above 1.0 on
  purpose, because a Crawler's capsule **top** is its 1.6 m plus its 0.6 m radius and a Breaker's
  is 3.0 m.
- **Rounds all land on whichever Breaker is nearest**, so a loop that meant to hurt both killed
  one and never touched the other. Five rounds into *one* of them is the better composition
  anyway: "distinguishable from a fresh one" is a claim about two bodies in one frame.
- **Seven seconds of settle is a photograph of a pile.** Thirty seconds at a slowed walk is what
  separates the release order into a column, and it is what lets a hurt Breaker, a fresh one and
  a death be three things in a frame. Also the frame is taken **six ticks after the killing
  shot**: #69's tracer is a rod from the muzzle to the body, and a camera standing off to the
  side sees it as a cream ramp across half the picture.

**No balance number moved and no Simulation state was added.** The wound is `query_enemy_health`
over `query_enemy_max_health`, the seed is `query_enemy_serial`, the flash is a diff in `game/`,
and `test_asking_what_a_wound_looks_like_leaves_the_run_exactly_where_it_was` is the assertion
that the Run which is watched is the Run that would have happened unwatched.

**What no still image can settle**, and the second of these is the ticket's own question. Whether
a quarter-second burst and a two-and-a-half-second stain read as a death or as litter over the
hundreds of kills a Run contains — `DEATH_BURST_TICKS` and `DEATH_MARK_TICKS` are the levers, and
both are constants in `game/` because the Simulation reads neither. And **whether a Siege Hulk's
frontal armour now reads as a discovery rather than as a broken gun**: a round into the glacis
takes 2 of 1800 and lights the body for eight ticks, so the flash says *that* it connected while
the cracks say almost nothing about progress — which is exactly the honest picture, and whether a
player reads it as "wrong end" or as "wrong gun" is a judgement for somebody with a mouse.
`siege_hulk.frontal_armour_percent` was left alone, as the ticket asked.

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

### And nothing noticed when the output was older than the recipe

#57, and the hole is the same one from the other end. Those generated files are
**gitignored**, so no commit, no diff and no test in any of the three suites has ever
related one to the script that produced it. Measured: `convert_weapons.sh` was corrected
and merged and the shipped `.glb` stayed **eleven hours older than the script** — three
suites green, because none of them can see a gitignored file — and the fix was reported
to the user as landed while the thing in their hands had not changed. It was found by
reading a timestamp by hand, on the third report of the same defect.

`tools/assets/asset_staleness.py` is the check. `tools/assets/run_tests.sh` runs it and
prints the report; `tools/release/preflight.py` makes it a **hard stop** beside its
missing-asset audit. The split is which question is being asked: a suite answers "is this
code correct", which is a property of the tree and the same for everybody who checks it
out, where a release is where *this machine's* build products become the thing in
somebody's hands — and that is the failure the ticket was opened about. Making it a
property of the **tools** rather than of CI is `wav_to_cue.FFMPEG_MINIMUM_MAJOR`'s
precedent, and here it is doubly necessary: **CI is the one machine that can never see
these files at all.**

Four things worth knowing rather than rediscovering:

- **Absence is not staleness, and that rule was not weakened by one word.** A file that
  is not there is reported by nothing. The only detectable case is a generated file that
  **exists** and is **older than its own recipe**, which is exactly the case that bit, and
  a clone with no packs gets the three groups' full file lists with every entry absent —
  so it is silent by construction rather than by a flag. A zero-byte file counts as absent,
  because `manifest.audit` already calls it missing and two complaints about one file would
  be one too many.
- **A file's age is when its content last changed, and a tracked file's mtime is a
  *checkout* date.** Every tracked file in a fresh clone — and in every agent worktree here
  — is minutes old, while the generated output it is compared against was produced hours
  earlier in the main checkout and reached the worktree through `link_licensed.sh`'s
  symlinks. Measured: a plain mtime comparison calls the entire pipeline stale with nothing
  edited, and a check that cries wolf in the normal case is a check somebody switches off.
  So an untracked file is as old as its mtime, a **modified** tracked file is as old as its
  mtime — which is what catches somebody mid-change before any commit exists — and a clean
  tracked file is `min(mtime, commit date)`. One rule on both sides, so a checkout can
  neither invent staleness nor hide it. With no git at all the answer falls back to mtimes
  and **says so**, which is the treatment `wav_to_cue` gives an ffmpeg with no release
  number.
- **The Machine meshes are deliberately not a fourth group, and that was measured.** They
  are the one case where staleness can be **proved** instead of guessed at, because both
  ends are committed and the generator is deterministic —
  `test_generated_machines.RegeneratingFromTheDeclaration.test_reproduces_the_committed_meshes_byte_for_byte`
  regenerates every mesh and compares the bytes. Including them anyway was tried and was
  worse than useless: five of the eleven committed meshes carry an older commit date than
  `machine_specs.py`, and regenerating `press_mk1` produced a file **byte-identical** to the
  committed one, so the group reported five false positives on a clean tree and would have
  taken the three real groups down with it. **Where the output is committed, prove it; where
  it is gitignored, date it.**
- **It proves it fires by backdating a file.** `tools/assets/tests/test_asset_staleness.py`
  builds throwaway git repositories — `test_licence_guard.py`'s shape — with the real
  recipes committed into them, and backdates a generated file rather than trusting whatever
  is on the developer's disk. It **never skips**, because a licensed-asset skip is a failure
  in `.github/ci/expected_skips.txt`'s own terms and a staleness check nobody has watched
  fail is indistinguishable from one that has quietly become a no-op. Checked by neutering
  the comparison: six of its fourteen tests go red.

**The first run of it found a live one.** `tools/assets/convert_audio.sh` was last changed
by the merge `2de7904` ("Merge #35 into #42"), which altered the recipe against *both*
parents, and all 55 cues in the main checkout were cut before it. So the hero audio on this
machine is the output of a recipe that has since changed — reported rather than re-cut,
because re-cutting writes into the quarantine every agent on this machine shares. The fix is
`bash tools/assets/convert_audio.sh`.

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
content/structures.csv  one row per thing that is built and is not a Machine: Belt, Wall
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

**A Machine is a row in two files since #47, and that is the one qualification on the sentence
above.** It needs its Recipe in `recipes.csv`, as it always did, and now also its ports in
`content/machine_ports.csv` — because a Belt docks against a declared port and nowhere else, so
a Machine with none is a Machine no Belt can reach. The loader refuses such a set by name rather
than letting it stand unreachable. It is still data and still not a code change; what changed is
that the declaration which was art's half is now the game's rule, and it has to be filled in.
`content/structures.csv` is deliberately **not** extensible in the same way: the structures are
`belt` and `wall`, because those are the intents that exist.

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

### One tuning fixture, and the cascade it used to cause

**Adding a required key to `content/tuning.toml` costs nothing in the suite, and that is new.**
Until #51 it cost about **156 failures across nine files**, because eleven copies of that file
lived inside ten test fixtures. Two tickets in one day paid it: #47 hit the same wall from the
content side and had an escape (a caller that supplies no structures source gets structures
that are **free**, which is what an empty `build_cost` column already means), and #49 added two
required tuning values, which have no such escape — ten fixtures learned the keys by hand, #49
reported three green suites on its own branch and went red on the merged tip, and #48 was
blocked behind the repair because it had merged integration mid-flight.

**The rule that makes the cascade is right and was not touched.** A set with any error carries
no definitions at all, because half a definition set is more dangerous than none — it looks
usable. 156 failures were that rule working exactly as designed. The defect was the
duplication that made one key touch eleven files.

**`tests/content_fixture.gd` is the whole of the fix**, and the shape is
`test_machine_mortality.gd`'s generalised — that file never carried a copy, and substituted
against the shipped file with pairs like `["breaker_damage = 60", "breaker_damage = 10000"]`.

```gdscript
var content: Definitions = (
    ContentFixture
    . for_case(self)
    . tune([["decay_per_minute = 240", "decay_per_minute = 0"]])
    . stock("iron_plate:400")
    . definitions()
)
```

- **Every source defaults to the shipped file and is a plain field**, so a test that wants
  Recipes it controls assigns `fixture.recipes` and changes nothing else. That ability is
  load-bearing, not an oversight — `test_depth`, `test_turrets`, `test_heat`, `test_world_view`,
  `test_enemies` and `test_nest` substitute a Delivery chain that locks nothing and a stock that
  pays for anything *precisely so* the chain is not what they are asserting.
- **The two optional tables default to absent**, not to the shipped file, because
  `Definitions.parse` does: no ports source is the loose docking rule, and no structures source
  is #47's escape. A fixture that quietly supplied them would change what every existing test
  means.
- **An override whose text the shipped file no longer contains is a failure naming it.** That is
  why the fixture holds the `TestCase` — `String.replace` returns the string unaltered and says
  nothing, so a renamed key would otherwise leave a test asserting against content it did not
  choose with **nothing going red**, which is a worse failure than the cascade it replaces. A
  *multi*-match is not refused, because deliberately changing every occurrence is a legitimate
  thing to ask for; keep a target unique if you do not mean that.
- **`stock(bill)` rewrites `player.starting_stock` by key, never by a copy of its value.** Ten
  files named `starting_stock = "iron_plate:110"` by hand, which is the same defect one line
  long — #47 moved that bill from 80 to 110 and had to touch all ten.
- **`tests/cases/test_content_fixture.gd` is its contract**, like `Fixed`'s and
  `InputQuantiser`'s, because what would go wrong with it is silence. It asserts the override
  *reaches the definition set* and that a stale one is reported — a helper that quietly returned
  the shipped defaults would make several suites assert against content they did not choose.

**What the migration found, and it is the ticket's own argument restated.** Six values were
identical in all eleven copies and differed from the shipped file: `view_kick_recover_seconds`,
`first_wave_interval_seconds`, `bob_stride_metres`, `holster_seconds`,
`look_sensitivity_turns_per_1000_pixels` and `walk_deceleration_metres_per_second_squared`. None
of them was an override anybody chose. They are **old shipped values the copies froze** — so
nine files had been running on balance the game stopped shipping, silently, and nothing could
have said so. Dropped where no assertion depended on them; kept as *explicit* overrides in
`test_first_person`, which pins its sensitivity and deceleration on purpose and says why.

**The CSV tables were considered and deliberately left alone.** Recipes and Machines are also
supplied by hand in several suites and the cascade risk is real — `CsvTable` errors on a missing
column, so adding one to `machines.csv` breaks every fixture that spells the header. But the
shape of the fix is not this one: those fixtures supply *different rows*, a deliberately minimal
two-Machine Factory that is legible where the shipped seven would not be, so a shared helper
would need row-level editing (replace by id, add, drop) rather than text substitution. What is
available cheaply is `ContentFixture.shipped(Definitions.MACHINES_FILE)` for a test that wants
the real table, which is what replaced ten private copies of a `_read` helper. The row-editing
version is a ticket of its own, and the day to write it is the day a column is added.

### Nothing in `tests/` reads a content file by hand any more

**#63 finished the migration #51 opened, and the list was longer than the ticket's.** #63 was
written against "the ten files that still carry a private `_read`"; what a grep for
`FileAccess` rather than for `_read` actually found was **nineteen**, and that difference is
the finding. Eleven carried a private `func _read`; two more carried the same reader under
another name (`test_declared_ports._tuning`, `test_structure_costs._own_tuning`); and **six
read `content/` inline at the call site**, which no search for a helper name would ever have
turned up — `test_world_view` seven times in one file. Four of the nineteen also carried a
`SHIPPED_STARTING_MACHINE` literal beside their `SHIPPED_STOCK` one, which #55 had just
added. **This is #55's own lesson about grep arriving a second time**: searching for the
shape of the workaround finds the files that chose that workaround, not the files with the
problem.

Grep `res://content` under `tests/` now and there are **no** hits outside `ContentFixture`.
Grep `FileAccess` and the only hits are the fixture itself, the two purity lints that walk
`sim/`, `test_definition_watcher` writing its own temporary files, three `file_exists` checks
about audio, and the one deliberate exception below.

- **`ContentFixture.starting_machine(id)` is `stock(bill)`'s twin**, and it exists for a
  sharper reason than tidiness. `player.starting_machine` names a **row**, so a fixture that
  brings its own `machines.csv` has to point it at a row it actually has or the whole set is
  an error carrying no definitions at all — which is why four files grew the literal in the
  first place. Both go through `_rewrite_quoted_key`, which replaces the whole line **by key
  name** and fails naming the key if there is no such line.
  `test_content_fixture.test_the_starting_machine_is_replaced_without_naming_the_shipped_row`
  and the error case beside it are its contract.
- **`tune_key(key, value)` is the third rewrite and it replaced two verbatim copies of
  itself.** `test_movement_weight._sim_with` and `test_godot_layer_smoke._sim_with_tuning`
  were the same twelve-line by-key line rewrite, each with its own `assert_true(found)`. Use
  it over `tune` wherever the **key** is what a test asserts about rather than the value it
  is replacing: "0 turns the bob off" is a claim about the key, and a pair naming the shipped
  amplitude would make it a claim about one number as well. `stock`, `starting_machine` and
  `tune_key` all go through one `_rewrite_key`.
- **`test_content_fixture._read` is the one private reader that stays**, and it says so in a
  comment: that file is the fixture's contract, so the reader it compares against has to be
  an independent one. Asking the thing under test to read the file it is being checked
  against would assert nothing.
- **A fixture per file, not a call per site.** Five sites in `test_silo`, four in
  `test_turrets` and seven in `test_world_view` each spelled out the same four or five
  decisions; each file now has one `_own_machines` / `_ammo_fixture` / `_fixture` helper that
  carries them, and a site that differs assigns the one field it differs in. That is what
  makes "this site brings its own Machines" and "this site gets the override" one decision
  rather than two, which is the arrangement #55 asked for by name.
- **What `tune` cannot protect is still unprotected, and #63 found a live one.**
  `ContentFixture` guards substitutions against the *tuning* source; a `String.replace` into
  a **table** a fixture brought itself is still silent. `test_silo._fragile_content` carried
  `SILO_MACHINES.replace("silo,4,4,0,0,900", "silo,4,4,0,0,120")` and the Silo row has
  spelled a `height_metres` column since #30, so the text was `silo,4,4,2.2,0,0,900`, the
  substitution matched nothing, and that fixture's Silo has stood on its full 900 hit points
  ever since — inside its own 6000-tick bound, so no assertion could see it. The dead
  substitution is **gone rather than corrected**, because correcting it changes how long the
  fixture takes to reach the thing it asserts. The general lesson is #51's pointed one step
  further: **a helper that makes tuning loud makes the tables the quiet place.** The
  row-editing fixture #51 deferred is where that gets fixed.
- **Three frozen things were found and none of them was a tuning value**, which is the other
  half of the answer to "what does the duplication hide". #51 found six frozen *numbers*
  because the copies held numbers; these nineteen substituted against the shipped file, so
  what froze instead was **prose**. `test_gear` said its acceptance test builds a line "out
  of the eighty plates a Run opens with" — the bill has been 110 since #47. `test_turrets`
  picks the second its Breaker fixture pulls the lever against "the shipped cold interval is
  150 s" — #35 split `heat.first_wave_interval_seconds` off at 90. Both are corrected or
  flagged in place; neither moved a number, and the fixture that reads 150 is still green,
  because what it needed was *enough* time rather than that time. The lesson is that a
  substitution against the shipped file protects the **value** and not the **sentence next to
  it**, so a file that was migrated out of #51's cascade can still be lying about the balance
  it runs on.

`Definitions.load_from_directory` reads all eight files and `Definitions.parse` takes all
eight sources, in that order. A missing one is an error naming the path, never an empty
table — and `game/definition_watcher.gd` digests all eight plus the ports, so editing any of
them hot-reloads.

The **order they are read in** is not the order they are listed in, and it is load-bearing:
Recipes first (the Items are interned from them), then Machines, then the **structures** —
because a Belt's `build_cost_per_tile` names an Item and is checked by exactly the rule
`machines.csv`'s `build_cost` is — then Gear, then the
**Stratagems** — a `sentry` row has to name a Turret in `machines.csv` — then the Waves, then
the Deliveries, whose three unlock columns each have to name a row in one of the tables above
— and **tuning last**, because `player.starting_weapon` has to name a weapon frame that no
Delivery tier locks, which is a question only the Gear table and the Delivery table together
can answer. The **ports** are read after all of it, because
`_check_ports_against_machines` asks about Machines and their Recipes together. Errors are
still gathered in *file* order, so the report reads like a list of things to go and fix.

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
- **A Node is ground you can see, and #52 is the ticket that cost.** A playtest said *"I
  cant seem to find any ore in range for the miners"*, and the snap was innocent: the ore
  was a 0.4 m slab in `Color(0.45, 0.32, 0.18)` on ground #20 and #42 made worn brown
  concrete, rust and soot. **Four times the palette's own albedo and still invisible**,
  which is the third time this project has paid for a colour picked against a white
  background — brightness was never the lever, because the slab shared its *hue* with the
  rust it was lying on. **Nothing on the ground plane wins a contrast fight against the
  ground plane.** So the seam came down into the palette (`ORE_IRON_GROUND`,
  `ORE_COAL_GROUND`) and two unshaded marks do the finding, drawn through one MultiMesh:
  - **A marking painted on the ore and a stack of segments floating above it**, because
    two viewpoints need two marks. A render settled it: from Survey View — the one mode
    this game has for reading the whole yard at a glance — a vertical mark is a 0.6 m
    square seen end on, and the first survey shot showed no ore at all. The stack is what
    reads across the yard, the marking is what reads from above, and the marking is also
    what gives the floating stack an owner (#41's lesson: a bright mark with nothing under
    it belongs to nobody).
  - **Paint, not a plinth.** A Miner is placed *over* a Node, so a mark that read as
    occupied would trade one confusion for another. `ground.gdshader` already draws the
    grid as paint, and paint is the one thing on a floor that is unambiguously not an
    object standing on it.
  - **One segment per Depth tier, so "deeper" reads as "taller mark"** and the tiers need
    no key. The base is 1.3 m and a render is why it is not 5: it was 5.0 first, reasoned
    off the marks a Machine on the same tile could wear, and at the *real* spawn distance
    a mark 5 m up sits 21 degrees above the horizon with nothing visibly under it. The
    collision it was avoiding cannot happen anyway, because the marks leave the moment
    anything is built on the Node.
  - **Colour says Resource and reachability: iron is rose, coal is cyan.** Red is a
    mistake, amber is waiting, hazard yellow is attention, teal is a split flowing, warm
    orange an output port, cool blue an input, cream a flow arrow — every one of those is a
    mark *about the Factory*, and a Node is the Map, like a Breach, so it reads in a family
    the Factory does not use. Ore no unlocked Miner could lift goes inert steel rather than
    a dimmed version of its own colour, the decision `PENDING_BREACH_HEIGHT_METRES` already
    records for a Breach about to open: the actionable fact is "not yours yet", and a dimmed
    colour reads as an artefact.
  - **The first pair was green and violet and a render threw it away, which is #48's
    finding again.** `HOLOGRAM_ALLOWED` is green, and the scanner below runs exactly when a
    Miner is on the Build Gun — which is exactly when a green hologram is standing on the
    ore. Three greens in one frame: the trail leading you there, the ore's own mark, and the
    ghost of the Machine about to land on it. #48's was a red post on an orange arrow at the
    one tile the two must coincide. **The colours to check a mark against are the ones it is
    guaranteed to be seen beside, not the ones it merely shares a file with** — and the only
    way either was found was by looking at the picture.
- **Three projections carry it, and each exists because two callers must not disagree.**
  `query_node_is_workable_now` is the unlock set, the Resource and the Depth tier read
  together — the mark's colour and the objective line's target come out of the one
  function, so a beacon cannot promise ore the hint will not send a player to.
  `query_node_is_built_on` is geometry, and the weaker claim on purpose: what the mark and
  the line share is *this is ground nothing more can be put on*. `query_player_facing`
  hands out `_facing`, so a caller saying "to your right" does not own a second copy of
  the yaw convention. None is read back and each has a test that asking leaves `hash()`
  where it was.
- **Covering a Node is not working it, and that was a live defect.**
  `query_node_under_machine` is geometry; an iron Miner over coal and a Mk1 on a Depth 2
  seam both cover a Node and accumulate nothing. `Objective` read the geometric answer, so
  a Miner on the wrong ore reported the opening step done. `query_node_is_being_worked`
  asks it of `query_machine_is_starved` instead, which keeps the question on
  `_machine_has_its_inputs` rather than on a list of cases somebody has to maintain.
- **Where a Run actually starts, measured rather than assumed.** A player opens at the
  origin on the ground — **not** on the Nest's crown, which is where `_respawn` puts them
  after a death. The nearest iron is **12.7 m** south-east, the coal 26.6 m east and the
  far iron 23.7 m north; the Depth 2 and Depth 3 seams are 49.7 m and 66.7 m out. So the
  opening walk is a few seconds and `MapLayout.starter()`'s "a Belt between them is a
  decision rather than a formality" is intact. **No Node moved for #52 and none needed to.**
- **The scanner is how a player is pointed at ore, and the player specified it:** *"we
  need a sort of scanner to ping the nearest node while putting down miners"*. A run of
  pings travels the ground from the player's feet out to the nearest ore they could claim,
  in that ore's own colour, so the thing that leads you and the thing you arrive at read as
  one. It answers direction, distance and identity at once.
  - **"While putting down miners" is three facts, each read off its own query every
    frame**: the Build Gun is in hand, the Machine tool is out, and what is on it mines.
    Nothing is remembered and there is no scanner mode to enter. It also goes quiet the
    moment the Factory is mining, on `query_anything_is_mining` — the same question
    `Objective`'s opening line goes quiet on, so the two cannot disagree about whether the
    opening has taught itself.
  - **`SCANNER_PERIOD_TICKS` is a count of ticks and that is the rule rather than a
    preference.** Nothing presentational here is timed by a clock: the audio director varies
    takes with `tick % count` and counts cooldowns in ticks, and `WeaponViewmodel` computes
    clip time from the tick and seeks explicitly. What all three buy is that two Runs down
    the same script look the same, and `test_world_view` asserts it from both sides — a
    frame that stepped nothing draws the same sweep, and one whole period on it is back.
  - **Only the lit pings are drawn at all**, and the sweep starts at the player's own feet.
    A full dotted line standing on the ground is a path through the yard — scenery — where
    a scanner is a thing that *sweeps*, and the empty ground between sweeps is most of what
    makes it read as one. Starting at the first step instead of at zero left the first
    seventh of every period with nothing lit, which reads as broken rather than as between
    sweeps.
  - **It is deliberately silent.** `game/audio_director.gd` would take a cue, but this
    fires every 90 ticks for as long as a Miner is in hand, and a repeating tone is exactly
    the nagging the player has already rejected three alarms for. Nothing in this repository
    can listen, so an un-auditionable cue added to a mix with three outstanding complaints is
    the wrong risk. The lever, if it is ever wanted, is a `sustained_cues` entry keyed on
    acquisition — a *change* — rather than on every sweep, with a hero take and a Kenney
    fallback like every other cue.
- **`tools/visual/compose_spawn_shot.gd` frames what a player sees the moment a Run
  starts**, and it is the one view no composer framed. It refuses to improve the vantage:
  no walking, no aiming, the camera wherever the Simulation put it. `spawn` is the opening
  yaw, `turned` faces the nearest shallow ore and `survey` does the same from the lift.
  Before and after are in `docs/images/ore_{spawn,turned,survey}_{before,after}.png`.
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
- **`content/machine_ports.csv` is the rule, since #47.** #19 added the file and the mesh
  markers that match it; #36 made the renderer draw an arrow on every declared port; and until
  #47 `_load_from_port` and `_hand_off` still took **any footprint edge tile**, so a player was
  shown a rule the Simulation did not enforce — which is worse than teaching them nothing.
  `_machine_behind_belt` and `_machine_a_belt_feeds` now answer -1 for a Belt standing against
  a wall that is not a declared port, or running the wrong way out of one, and every other
  consumer reads those two functions: the load, the hand-off, the blockage report, and the red
  post `query_belt_start_is_fed` puts at an entry nothing feeds.
  - **A face is declared tile by tile, and that is what the table grew for.** A port is one
    tile wide, so a Machine whose goods cross a whole face carries one row per tile of it. Two
    things force that rather than a single port per good. #46 made a Machine serve several
    Belts in rotation — a factory game's second verb after laying one — and a Machine with one
    declared output could never branch. And declaring only the middle tile of a 3-wide face
    would make *which tile a player aimed at* the difference between a line that works and one
    that does not, for no reason a player could see. So the shipped table went from 21 rows to
    **93**, and the arrows now draw along whole faces, which is more legible rather than less.
    (This line said 77 until #48 counted the file: 93 is what `content/machine_ports.csv` holds
    and what #47's own commit message says, so the prose had been written mid-ticket and not
    re-read. Every other claim in this section was checked at the same time and holds — every
    id in `machines.csv` declares ports, the five rows naming no Machine are exactly the
    documented warning cases (`press_mk1`, `assembler_mk1`, `generator_mk1`, `nest`,
    `belt_straight`), and `_ports.feed_into` really is in `Definitions.digest`.)
  - **The port says where, not what.** A Belt docking at a declared input port may carry any
    Item the Recipe wants; `_accept_input` decides that and always did. The good in a port_id
    is the intended routing rather than a restriction — a Smelter takes ore on its north face
    and coal on its west one by design, and feeding ore in from the west works.
  - **Two cross-checks replace the old looseness, and they point in opposite directions.** A
    Machine that takes a Belt-fed input and declares no input port, or produces an Item and
    declares no output port, is an **error naming the row** — because after this change such a
    Machine is one no Belt can reach. That is what made the Turret's ports impossible to forget:
    it had no row at all and would have docked nowhere. A row naming a Machine `machines.csv`
    does not define is a **warning**, not an error, and the distinction is the point: the
    Nest's delivery port and a Belt's own two ends are legitimately not Machines, and
    `machine_bodies.csv` legitimately declares bodies — `press_mk1`, `assembler_mk1`,
    `generator_mk1` — that `machines.csv` has not caught up with. Data nothing reads is what a
    warning is for, which is the treatment a tuning key nothing reads already gets.
  - **It is in `Definitions.digest()` now**, and it was out of it before for a reason that
    stopped being true. The digest is the set of numbers a Run is playing by; while the ports
    were drawn and nothing else, a client whose table differed drew different arrows and
    simulated the same Run. A client whose table differs now carries goods across a different
    wall, so the digest is what refuses that rather than letting it desync.
  - **A set with no ports table at all is still the loose rule**, and that is honest rather
    than a loophole: a declaration that does not exist cannot be enforced. It is the seam every
    test that brings its own Machines works through, and it is the same shape as a Machine with
    no generated body drawing a box. What stops `content/` reaching it is the error above.
  - **The Nest is deliberately not enforced.** It is not a Machine (GLOSSARY.md), and
    `_hand_off` reaches it through a clause of its own rather than through a Machine's ports —
    so a Belt into the Nest docks anywhere on its 4x4 wall, as every Delivery line in every
    scenario already does. Its row in the ports table is there because the mesh generator needs
    it.
  - **A Belt that will not dock says what would make it dock, and that is #56.** The rule was
    enforced and the arrows were drawn, and the **consequence** was not said: a red post stood
    at the dangling end and nothing named the fix. A player who has not noticed the arrows
    reads that as a bug, which is worse than teaching them nothing — and #47 recorded the
    evidence that a person will, because `test_nest_store`'s own Factory needed exactly that
    fix from somebody who *had* read the table. See "Why a Belt will not dock" below.
- **A Belt is not a Machine.** No row in `content/machines.csv`, no Recipe, no `role`.
  GLOSSARY.md keeps the two apart and so does the code; `InputAction.Kind.BUILD_BELT`
  carries two tiles rather than a definition index.

### What is on the Belt, and that it is running

#73, and the complaint is this file's own standard turned on the one system it had never been
applied to. A Machine's **silhouette is a gameplay requirement, not polish** — the core skill in
a factory game is reading your own production line at a glance, and `machine_silhouette.py`
fails the asset suite if any two Machines converge. The **Items are the content of that line**,
and `_sync_items` drew every one of them as the same `BoxMesh` painted
`Color(0.62, 0.36, 0.20)` through one `material_override`: iron ore, coal, plate and Ammunition
were one picture, so a player looking at two Belts could not tell which carried the Boiler's
fuel and which the Press's plate. And the deck never moved, so the only motion on a working
line was its cargo sliding along a surface that was scenery.

**`game/item_appearance.gd` decides what an Item looks like, and it is not an Item table.** That
is the whole design problem: the set of Items is exactly what `content/recipes.csv` mentions,
interned in sorted order, and nothing in `sim/` names one — so a list of ids with colours
against them would be the second content table the project refuses. What is derived instead is
an Item's **standing**: what the Factory *does* with it.

- **fired** — a weapon frame names it in `ammunition_item`. Brass-cased rounds.
- **burned** — some `role=generator` Machine's Recipe eats it. A generator is a crafter that
  makes nothing, so "a Boiler eats it" is the whole definition of fuel and it needs no column.
- **dug** — every Recipe that yields it yields it out of nothing, because a Miner's input is the
  ground under it. That *absence* is the definition; nothing reads the word "ore".
- **made** — anything else.

Four facts about the Recipes, the Machine roles and the Gear table, and
`test_asking_what_an_item_looks_like_names_no_item_id` asserts the absence of an id in that file
the way build mode's criterion is written as the absence of code. Add an Item to the Recipes and
it is drawn correctly with no edit here and none in `world_view.gd`. It lives in `game/` for the
reason `BuildChain` and `Objective` do, and asking any of it leaves the state hash alone.

**The shipped four land one in each form**, which is what makes a Belt readable rather than
merely painted, and `test_the_shipped_items_land_one_in_each_form` is that claim — a derivation
that collapsed any pair would pass every other test in the file and fail that one. The
precedence is load-bearing in both directions and each arm has its own test, because the shipped
content exercises one of them *silently*: coal is both dug and burned, so one answer is right
for two reasons, and the test that isolates it points the Boiler at iron ore instead.

**A form wears one of the palette's own committed materials** — `DullBrass`, `Soot`, `OxideRed`,
`WeldedSteel`, through the `assets/machines/materials/*.tres` the Walls and every Machine body
already draw. Per-instance colour was the ticket's stated minimum and a material is strictly
better: an instance colour multiplies **albedo** and says nothing else, and these surfaces are
physically based and mostly metal — the lighting takes ambient and reflections off the sky
precisely because a metal lit by an ambient colour renders as a dark smear whatever its albedo
says. Brass has to be metallic and smooth and soot has to be matte and black, and only
`metallic` and `roughness` can say so.

**One MultiMesh a form, built eagerly on the first sync**, so the scene tree does not grow by a
node for any amount of cargo — and that is the reason the look is keyed on a *form* rather than
on an Item. The form set is **closed**, so this is `EnemyKind.KIND_NAMES`' bargain exactly:
`test_cargo_is_never_a_node_however_much_of_it_there_is` asserts **zero** growth rather than "no
more than one per form". A MultiMesh per Item **id** would have grown the scene tree with
`content/recipes.csv`, which is the one thing the absence of an Item table exists to prevent.
What it costs is four buffers and four draw calls where there was one. `_item_transforms` stays
the flat array in the Simulation's own order, because that is what `item_instance_position` has
always meant and what a MultiMesh buffer cannot be read back out of — the arrangement
`_belt_transforms` already has.

**The deck runs on `game/belt_deck.gdshader`, and its speed is the Belt's own.** Cleats advance
**one Item slot every `ticks_per_item` ticks**, both read off the queries, so the surface moves
at exactly the speed of the cargo on it for any rating — 0.5 m every 15 ticks on the shipped
numbers, which is the Belt's 2 m/s — with no second number anywhere to disagree with
`belt.items_per_second` and `belt.items_per_tile`. Counted in **ticks**, which is the hard rule
the ore scanner's sweep and `WeaponViewmodel`'s clip time already obey, and
`test_the_deck_scrolls_and_nothing_about_it_is_timed_by_a_clock` asserts it from both sides: a
frame that stepped nothing draws the same deck, and one whole period on it is back.

Three things about the shader worth knowing rather than rediscovering:

- **The cleats are read in object space.** Every Belt body is modelled running along its own +Z
  and placed by a yaw, so `VERTEX` is distance along the run whichever way the line points. A
  world-space read would have made a north-south line and an east-west line scroll in unrelated
  directions, and a UV read would have depended on an unwrap the mesh generator may change.
  **Every tile is the same mesh instanced, so that coordinate restarts at every tile boundary**
  — which means the pattern is continuous along a run only because the pitch divides the tile
  exactly. It does by construction rather than by luck, since the pitch is `tile_size /
  items_per_tile`; a pitch picked by eye would have put a visible seam at every tile join. That
  is the second reason to derive it from the Belt's rating, beside matching the cargo's speed.
- **It is a shader and not geometry**, because a Belt tile is one instance in one MultiMesh
  shared by every Belt on the Map. Moving slats would be moving slats per tile, which is the one
  thing this system's data layout exists to avoid.
- **The deck surface is found by material name**, `BeltRubber`, which is what
  `machine_recipes.py` calls the running surface — so "the deck" is a surface this can ask for
  rather than an index to guess at, and the `BeltRubber` material's own albedo, texture, scale,
  metallic and roughness are carried *into* the shader rather than painted over. Asserted rather
  than assumed, because #49 is what an unchecked claim about a named surface costs: a branch
  written against geometry nobody had looked at sat in these notes as a fact for a whole ticket.
  `test_the_deck_that_scrolls_is_the_belts_own_rubber_and_not_its_frame` checks that the surface
  resolves and that **exactly one** scrolls — the rubber, not the frame, the legs or the stripes.

#### What the renders found, and the two plans they killed

The pair is [`docs/images/belt_cargo_survey_before.png`](docs/images/belt_cargo_survey_before.png)
against [`_after`](docs/images/belt_cargo_survey_after.png), and
[`belt_cargo_eye_before.png`](docs/images/belt_cargo_eye_before.png) against
[`_after`](docs/images/belt_cargo_eye_after.png), rebuilt with

```bash
tools/visual/shot.sh out.png survey
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png "running bare"
```

**The first plan was to sample the Item's own committed icon, and measuring it is what killed
it.** It is the elegant answer and the one the ticket points at — #59 committed a picture of
every Item and `WorldView.icon_path_for_item` is the one authority on whether it resolves, so
the cargo and the hotbar cell would have been the *same art* and could never disagree. Measured,
the mean of the opaque pixels is **(81, 69, 70) for iron ore, (59, 59, 61) for coal, (76, 76, 78)
for plate and (89, 90, 93) for Ammunition** — four near-identical greys, because the icons are
monochrome industrial art. Ore against plate is eight parts in 255 summed over three channels.
**The art cannot carry the signal**, and amplifying chroma from a near-neutral sample amplifies
noise rather than hue. That is the third time this project has been wrong about a colour it had
not measured, and the first time the measurement arrived before the render rather than after.

**The second was the geometry, and the render caught it.** The first pass spanned about 0.7 of
`ITEM_SIZE_METRES` against the solid box it replaced, which is half the screen area: from Survey
View the colour was right and the cargo had got *quieter*, which is the opposite of the ticket.
Worse, the forms straddled their own origin, so a stacked slab floated 9 cm over the surface a
player walks on — exactly the "an Item riding above the deck reads as a bug" #30 warns about.
Every form now **fills its envelope and stands on its own zero**, so it is *placed and never
measured*, the rule every Machine body already obeys, and the test asserts the drawn origin is
the deck to the centimetre rather than inside a band.

Two things the pictures settle, and one they do not:

- **From Survey View both halves land.** The deck reads as a cleated conveyor rather than a
  plank, and the ore is unmistakable rust-red rubble where it used to be an orange box in very
  nearly the port arrows' own colour — which is the same ambiguity #56 recorded for its red
  posts, freight and marks sharing a palette.
- **The cleats read brighter than their albedo, and that is the lighting working.** `WeldedSteel`
  is 0.14 against `BeltRubber`'s 0.3, so on paper the cleats are the *darker* material; they
  render as the lighter bands because they are `metallic = 1` at roughness 0.38 under a sky this
  project deliberately takes its ambient and reflections from. A cleat picked on albedo alone
  would have been picked on the wrong number.
- **At eye level the deck is not the read, and the cargo is.** Standing beside a line at the
  distance `running` frames, a Belt is seen edge-on: what fills the frame is its side trestle and
  the wall of port arrows above it, and the deck is a few pixels of grazing surface. The colour
  change carries that view on its own and the scroll does not reach it. That is honest rather
  than a defect to fix — a player walking their own line looks down at it — but it does mean
  **the scrolling deck is a Survey View and close-quarters read**, and nothing has watched a
  person decide whether it reads as motion rather than as a texture.

**What no still can settle** is the one thing the second half of this ticket is for: whether a
deck that scrolls reads as a machine doing work. A strip, one frame per tick, would show the
cleats advancing; it would not show whether the speed feels like the Belt's. The levers are
`cleat_width` and the cleat material, and both are in the shader rather than in tuning, because
the Simulation does not read either.

### Why a Belt will not dock, and the two answers

#56, and it is the half #47 shipped without. #19 declared every port, #36 drew an arrow on
each one, #47 made the declaration **the rule** — and the thing a player is told when the rule
bites was still a red post with no caption. A Smelter stood square takes ore on its north and
west and gives plate back on its south and east, so a line running east to west connects
**neither** of its Belts, and the fix is to rotate the Machine. Nothing anywhere said so.

The evidence that a person hits this was already in the repository and #47 wrote it down:
`test_nest_store`'s own Factory needed exactly that rotation, which means somebody who had
read the ports table still got it wrong. A player who has not noticed the arrows reads a
refusal as a bug, and the standing direction is that setting up a basic production line is
paramount.

**Two reasons, because there are two fixes**, and that distinction is the whole of the design
here rather than a nicety:

- **`NO_PORT_ON_THAT_FACE`** — that tile of that wall declares no port at all. Answerable by
  turning the Machine **or** by docking against a face that already has one, and the sentence
  names both: *"no port on that wall — turn the Machine, or dock on another face"*.
- **`PORT_RUNS_THE_OTHER_WAY`** — the wall *is* a port and it carries goods the other way. Only
  rotation helps, so only rotation is offered: *"that port runs the other way — turn the
  Machine"*. A face with a port on it is a face the player aimed at on purpose, so "aim
  somewhere else" would be advice about the one thing they got right.

**The rule has one home and it is the function that does the refusing.** `_dock_refusal` is
`_belt_docks_against`'s body — the old predicate is now one line over it, `return
_dock_refusal(...) == Refusal.NONE` — so what reports the reason and what refuses the hand-off
are literally the same code. That is the bargain `query_build_refusal` exists for and #35 is
what the other arrangement costs: four inline checks on one side and none on the other put a
green hologram over a click that did nothing. `_dock_refusal_ahead` and `_dock_refusal_behind`
take a **tile and a direction** rather than a Belt index, which is what lets the laid Belt and
the route in flight share one answer; a preview that said nothing and a Belt that then dangled
would be the same disagreement wearing a different hat.

Four projections, and the Simulation reads none of them back —
`test_asking_why_a_belt_will_not_dock_leaves_the_run_exactly_where_it_was`:
`query_belt_{start,end}_dock_refusal` about a Belt that is standing, and
`query_belt_route_{start,end}_dock_refusal` about a route nobody has committed to. **The
wording lives in `game/`**, in `BuildGun.refusal_text`, because a `Refusal` is a fact and a
sentence about it is presentation.

Three decisions worth knowing rather than rediscovering:

- **It is advice before the release and never a veto.** The route dock refusal is deliberately
  *not* folded into `query_belt_route_refusal`, which is the function that decides whether a
  route lays. A route whose far end will not dock lays perfectly well, and a player routes a
  line in stages past where the Machine is going to stand every day — refusing the drag would
  gate laying a Belt on the order they happen to do things in, which is the opposite of what
  this is for. `test_a_route_whose_end_will_not_dock_is_still_a_route_that_lays` pins it.
- **An end on open ground gets no port sentence.** `_dock_refusal_ahead` answers `NONE` when
  there is no Machine beyond the end at all, which is not a gap: that end is dangling because
  it wants a longer Belt, the red post already says so, and a port sentence there would be
  advice nobody can act on — #41's ownerless mark in words rather than in geometry.
- **One sentence per reason, not one per Belt.** The mistake is almost always made at both
  ends of one line at once, so the HUD collects distinct reasons. The count stays on the
  dangling-ends clause where #36 put it: the mark says *where*, the count says *how many*, and
  this says *what to do*.

`MachinePorts.declares_a_port_at` is the only new question the table had to answer, and it is
deliberately **not** an authority on docking and deliberately does not return the flow.
`has_port_at` remains the one function that says whether a Belt may dock and is asked first;
this only classifies a failure that has already happened. Returning the flow instead would be
a second opinion about which way goods cross a wall — and a face could in principle declare
both flows, where "is it a port" has one answer and "which way does it run" would have two.
The extra walk of the ports is therefore paid only on failure, so the hottest loop in the
project is untouched.

**Nothing behind the façade changed its behaviour**, which is why no new determinism fixture
was written: `test_declared_ports.gd` already replays a Factory with one Belt docked and one
refused, and that fixture is what covers the code this moved.

**What a face with no port at all means on the shipped content, which was a finding.** Counted
across `content/machine_ports.csv` against each Machine's footprint, **eight of the ten
Machines declare every tile of every face** — so `NO_PORT_ON_THAT_FACE` is reachable from
`content/` through exactly two of them: the **Steam Boiler**, whose southern face (3 tiles) and
whose eastern tile 0 declare nothing, and the **Silo**, whose southern and eastern faces (4
tiles each) declare nothing. Both are Machines in the opening and mid-game lines, so the reason
is not hypothetical — but it is worth knowing that the commoner mistake by far is
`PORT_RUNS_THE_OTHER_WAY`, because a fully-declared Machine has no blank wall to aim at.

#### What the renders found, and the one that changed the code

The pair is [`docs/images/dock_before.png`](docs/images/dock_before.png) and
[`_after`](docs/images/dock_after.png) — a Smelter with a line arriving at the wall plate
comes *out* of, and a Steam Boiler with a line arriving at the wall that declares nothing —
rebuilt with
`SHOT_SCRIPT=tools/visual/compose_dock_shot.gd tools/visual/shot.sh out.png bare`.

**The first render found a defect no test could have, and it is #48's second finding arriving
in the one place #48 wrote off.** `BRANCH_MARK_HEIGHT_METRES`' note ends: a branch post had to
stand clear of the port arrows because a branch's entry tile *is* a dock tile, and "nothing
else in this file collides with them, because a dangling end has no Machine behind it and
therefore no arrow." **The end this ticket is about is the counter-example** — a Belt refused
by a declared port is standing on a dock tile by definition — and the render showed exactly
what the note predicts for anything that does: a 0.44 m red cube at 1.1 m, half inside a 0.9 m
conveyor deck, among 3.2 m warm-orange arrows. At four metres it is findable; at the distance
a player reads a Factory from, the counter said four posts and the picture had none.

So `DANGLING_AT_A_WALL_HEIGHT_METRES` is #48's own 2.25 m reused for the collision it was
measured against, and **which height a post gets comes off the dock refusal** — the same
projection the sentence does, so the mark that says *where* and the line that says *what to
do* cannot end up about different ends. An end on open ground keeps the hip-height post,
because there is nothing there to clear and a post three metres over bare ground is #41's
ownerless mark. `test_a_post_at_a_machines_wall_stands_clear_of_the_port_arrows_under_it` is
the assertion, and #48's note has been corrected rather than left standing.

Two more things the pictures settle:

- **The before image is the argument.** The same Factory, the same two refused lines, and the
  HUD says only `4 belt ends lead nowhere`. The posts sit flat on the decks, where they are
  the same size and very nearly the same colour as the ore Items riding past them — so the
  one mark a player had was not merely unhelpful, it was ambiguous with freight.
- **The vantage is a finding of the same shape as #48's fourth.** The camera is framed on the
  two refused ends **read back out of the Simulation** rather than on the tiles the composer
  asked for, after a first attempt placed from the latter put both marks off the edge of a
  picture whose counter said four. A composer that frames from what it meant to build is a
  composer that cannot catch a mark in the wrong place.

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

**A Belt costs a plate a tile, and the HUD's route line says what the route will cost before
the release.** #47 gave Belts and Walls a price in `content/structures.csv`, which is the table
that owns both — see "What a Belt and a Wall cost", below. The length was always the number a
player decides on; now the bill beside it is the consequence of that decision, which is what
makes laying out a Factory a question of routing rather than of taste.

#### What colour a route is, and the three places that disagreed about it

**#67, and it is #35's defect arriving in the Belt tool a ticket at a time.** The render that
opened it is one frame of a drag in flight, and three things in it contradicted one another:

```
aimed at -6, 10 — cannot build there — something is already standing
belt: release to lay — 10 tiles — iron_plate 10 — cannot build there — something is already standing
```

— under a route drawn in **green**, which is `HOLOGRAM_ALLOWED`, the colour a player learns off
the Machine hologram as *click and it goes down*. All three faults were real and all three were
different, which is why the first job was separating them.

- **The preview was the liar, and the rule it had was only part of the rule.** A route **lands
  whole or not at all** — `_apply_build_belt` consults `_belt_route_refusal` over every tile
  before the first Belt appears — and the preview tinted **tile by tile** off
  `query_belt_tile_refusal`, which is one clause of that function. So a ten-tile route with one
  blocked tile drew nine tiles in the allowed colour and laid **nothing**. The colour now comes
  off `query_belt_route_refusal`, the same door the release goes through, which is the one home
  #35 bought and the Belt tool had never been given.
  - **`MISSING_MATERIALS` is the proof the per-tile tint could never have been enough**, and it
    is the purest version of the bug rather than an edge case: every tile is clear ground, no
    tile is markable, and the release is refused for the plate. Before #67 that drew a full
    route in green and laid not one tile.
  - **The per-tile red stays, and the two marks answer two different questions.** The colour of
    the route says *whether*; the standing red volume says *where*. A blocked tile is a place, a
    refused route is a verdict, and collapsing either into the other loses the half a player
    acts on.
  - **The dock refusals are still not consulted, and that is deliberate rather than an
    oversight.** A route whose far end will not hand its goods over lays perfectly well, because
    a player routes a line in stages past where a Machine is going to stand every day (#56).
    Advice before the release, never a veto — and therefore never a colour.
    `test_a_route_whose_end_will_not_dock_still_previews_as_one_that_lays` is that sentence from
    the renderer's side, beside the Simulation-side test #56 left.
- **The belt line's verdict was right and its invitation was printed beside it unconditionally.**
  `release to lay` and `cannot build there` cannot both be true of one route, so the lead clause
  reads off the same refusal the verdict does and says `will not lay` when it will not. One
  function, two clauses of one sentence, rather than two opinions.
- **The `aimed at` line was about the wrong tool entirely**, and so was the `build gun:` line
  over it. Both asked `BuildGun.placement` about the Machine on the gun whichever tool was out,
  so a player mid-drag read a Miner's name, a rotation nothing would turn, and a refusal about
  ground they were not asking about — sitting directly above the route line, where it reads as
  the route's. **The panel describes the tool in hand**: with the Belt tool out those two stand
  down and `_belt_route_lines` answers, which is the question actually being asked.
- **And the objective line named a key for a tool already in hand.** `Press C for the Belt tool`
  in a frame where the Belt tool is out is an instruction to do a thing already done.
  `_with_the_belt_tool` is `_with_the_build_gun`'s shape one step further — a step's *wording*
  changing off a query rather than a step of its own, because "press C" is not a thing to
  achieve and a player who swaps back an hour in must be told the key again. The two clauses
  compose rather than race: a holstered player is told about `B` first, whatever is on the gun.

**The pair is committed and it is the argument.**
[`docs/images/building_routing_before.png`](docs/images/building_routing_before.png) against
[`building_routing.png`](docs/images/building_routing.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png "routing bare"
```

The `routing` preset has deliberately put a Wall on a tile of its own route since #36, so the
subject was always a refused route — what changed is that the picture now says so. Before: a
green run of tiles with flow arrows on it, one red marker in the middle, and two HUD lines that
contradict both the colour and each other. After: the whole route in the refused colour, the
marker still standing over the Wall that is in the way, and one line that says `will not lay`.

**And the render found the one cost of the fix, which is recorded rather than patched.** The
standing red volume that marks the blocked tile is now **red standing on red**: against nine
green slabs it was the only warm thing in the picture, and against nine refused ones it is
distinguishable only by being a box rather than a slab. It is still findable at the distance
the shot is taken from — the volume is 2.6 m against a 6 cm slab, so it has a silhouette and a
shadow — but the *where* is read second now where it used to be read first. Giving it a third
colour was the obvious answer and was not taken: this game has two hologram colours and a
player learns them off the Machine, and a third would be a new thing to learn in order to
answer a question — *will this go down* — that has two answers. If the render is wrong about
findability the lever is `BELT_REFUSED_HEIGHT_METRES`, not a third colour.

**What no render can settle** is whether a whole route going red the moment a drag crosses one
bad tile reads as informative or as nagging, over the hundreds of drags a Run actually
contains. That is the same category as whether a priced Belt makes routing interesting or
fiddly, and it wants somebody with a mouse.

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

#### Drawing it, which is the half #46 could not do

#46 shipped the mechanic and recorded what it was missing: *"Nothing draws a split. A player
watching one Belt run full and the other half-empty cannot tell back-pressure from a bug."* #48
is that half. The Simulation knew three things a player could not see, and a mechanic a player
cannot read is indistinguishable from a bug — the argument Heat's visibility and the Turret's
Ammunition gauge both make.

- **Two projections, and nothing else behind the façade changed.**
  `query_machine_branch_count` and `query_machine_branch_belt` are `_machine_behind_belt`'s
  answer asked from the *other side* — per Machine rather than per Belt — over the canonical
  order `_load_the_ports` serves in, so the membership a player is shown is exactly the group
  the rotation is over. A Belt docked against a wall #47 does not declare an output on is not in
  it: not a branch that gets no turns, not a branch.
  `test_asking_about_a_branch_leaves_the_run_exactly_where_it_was` is the assertion that the
  hash does not move for being asked.
- **Blocked is `query_belt_is_stalled`, and "no room at the entry" would have been wrong.** A
  healthy saturated branch has no entry room on most ticks — the room check is what rate-limits
  loading to the Belt's rating — so a mark on that flickers on a line that is working perfectly.
  Stalled is the stable fact, and it is the one a player has to act on.
- **A mark only inside a branch**, deliberately. The confusion this exists for is *between* two
  Belts off one Machine; a single line that is backed up already reads as a Belt packed solid
  and is named in the HUD. A post on every stalled Belt in a late Factory is a post on most of
  them.
- **Three marks: a tag over the Machine, a post at each branch, and a different post at the
  blocked one** — plus the tag going hazard yellow when every branch is stopped and the output
  buffer is growing, which is the one moment a player needs telling that nothing is being
  destroyed. The HUD's brief panel counts them off the marks rather than working them out a
  second way, the arrangement its dangling-ends clause already had: the mark says *where*, the
  line says *how many*.

**Four renders decided the geometry and every one of them found something no test could.** The
before and after are [`docs/images/branch_before.png`](docs/images/branch_before.png) and
[`_after`](docs/images/branch_after.png), rebuilt with
`SHOT_SCRIPT=tools/visual/compose_branch_shot.gd tools/visual/shot.sh out.png [bare]`. In order:

1. **A branch post at 0.7 m is inside the Belt it is about.** `belt.deck_height_metres` is 0.9.
   The number had been picked to sit under the hip-height dangling post so the two would read
   apart, which is a reason about the marks and not about the world.
2. **Then it cleared the deck and was still invisible**, for a reason peculiar to this mark: a
   branch's entry tile **is a dock tile, which is exactly where #36 draws a port arrow**. Those
   are 3.2 m across, warm orange and flat at deck height, so a small red post among them is red
   on orange at the one place the two are guaranteed to coincide. Nothing else in `world_view.gd`
   collides with them, because a dangling end has no Machine behind it and so no arrow. The post
   now stands well clear above them.
3. **#41 bites in both directions, and `query_machine_height_metres` is the housing.** A tag
   2.1 m over a Smelter's declared 1.5 m is **inside its flue**, which reaches about five; the
   Miner's 1.8 m sits under a derrick. Hung off the drawn body instead it was seven metres up,
   overlapping the HUD, with nothing visibly under it — which is #41's actual symptom. So
   `_machine_roof` takes the **max** of the housing and the drawn body's own AABB, and the lift
   is the max of a small clearance over that body and a larger one over the housing that keeps
   the mark order Ammunition gauge → starved tag → split tag. Neither number is a constant
   standing in for a Machine's height. **The amber starved tag and the Ammunition gauge had the
   same defect and were deliberately left alone**, as a behaviour change to shipped marks with
   assertions pinning them; that was #50, and both now measure from `_machine_roof` too. See
   "Every mark hangs off the drawn body, not the declared housing".
4. **The vantage is a finding too.** A split leaves by a Machine's southern and eastern faces, so
   a camera to the west or north has one entry directly behind the body — and a mark that is
   behind something looks exactly like a mark that was never drawn. Three renders had a counter
   saying "1 blocked" and a picture with none in it.

`tools/visual/compose_branch_shot.gd` is a third sibling of `compose_shot.gd` and
`compose_building_shot.gd` and needed to be: the subject is twenty metres of Factory, which at
eye level is nose-first into a conveyor and from Survey View is a sixth of the frame under a wall
of port arrows. It places the camera, like the first, and keeps the HUD, like the second. It
carries `bare`, for the reason `compose_wave_shot.gd` does — the first dressed render had a
prop standing where the tag was, and "hidden behind something" and "never drawn" are two very
different bugs that look identical in a picture.

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
- **Enemies push one another apart, and until #76 they did not.** This line used to read
  *"Enemies do not collide with one another, by design. A swarm is a swarm, and the
  alternative is an O(n²) separation pass the Chaff tier could not afford"* — and the
  reasoning was sound about the pass somebody writes first. What it was wrong about is that
  the quadratic is avoidable: bucket the Map and each Enemy consults a bounded handful of
  neighbours however many are alive. The user looked at what the note produced on screen —
  a rank of bodies interpenetrating as they converge on one tile — and overruled it, which
  is theirs to do. See "Separation: a crowd rather than a rank", below.
- **An Enemy's tick now reads other Enemies, and that is the one invariant #76 had to buy
  back rather than inherit.** It was free while nothing did: index order carried none of the
  bias Belts have to avoid, because no Enemy's step depended on another's. Separation is
  paid for three ways instead — displacements are accumulated into per-tick scratch and
  applied after the pass, each unordered pair is visited exactly once, and the buckets hold
  each cell's members in index order — so what a body ends a tick holding is a property of
  where the crowd *was* rather than of which members of it were walked first.
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

### Separation: a crowd rather than a rank

#76, and it is the first ticket in this file to **overturn a design note rather than fill a
gap**. The note said Enemies do not collide with one another by design, because the
alternative is an O(n²) separation pass the Chaff tier could not afford. The user looked at
what that produced — *"dont have proper AI or collission"* — and overruled it. The reasoning
was right about the pass somebody writes first and wrong that there is no other kind, so what
had to be answered was the quadratic and not the mechanic.

**Separation is local and the flowfield is not, and nothing here touched the flowfield.**
Where a swarm is *going* is one shared field swept over the whole Map and amortised across
every Enemy alive, plus #34's second field and the lane a Breaker marches down under fire —
measured as worth two minutes of Run, and untouched. Where one body stands relative to the
body beside it is a question about a couple of metres, and `_separate_the_crowd` reads no
field, no path and no destination. It runs **after every Enemy has taken its step**, for the
reason `_load_the_ports` is a pass of its own: it is a decision *between* entities, and
deciding it inside the walking loop would decide it in the order the Enemies happen to be
walked in.

- **The buckets are a sorted array of packed keys, and both obvious structures were refused.**
  Each separating Enemy contributes one `cell * SEPARATION_CELL_STRIDE + index`, over the
  flowfield's own cell index space; sorting that groups the occupied cells and leaves each
  group in **index order**, and a `bsearch` then answers "who else is in this cell" without
  the array ever being walked as a whole. A **Dictionary** of cell to occupants is exactly
  what the purity lint forbids, and rightly — its iteration order is not a property two
  clients agree on, and #76 took **no new exemption**. A **head array over the field**, chained
  through a `next` array, is the textbook spatial hash and is genuinely O(n); it is also
  16,641 integers cleared on every tick of every Wave to serve twenty Crawlers, which is more
  work than the sorting it saves. The sort is over the Enemies that exist and nothing else.
- **How far the neighbour search looks is derived, not written down.** Two bodies interfere
  when they are closer than the sum of their radii, so looking one cell out finds every
  neighbour a body could owe a push to exactly when that sum fits inside a tile. On the
  shipped content it does — the widest separating pair is two Breakers at 0.8 m, which is
  1.6 m against a 2 m tile — so `_separation_reach_cells` answers 1 and the search is the nine
  cells the ticket described. It is computed from the largest radius any separating kind
  declares because the alternative goes **quietly** wrong: a later kind with a two-metre
  radius would make a nine-cell search miss the neighbour two cells away, and that does not
  fail, it just stops separating, which looks exactly like the old behaviour.
- **Displacements are accumulated and applied afterwards, and the honest argument for that is
  not determinism.** Applying in place would *also* replay — index order is ascending spawn
  serial and every client walks it — so this is not the desync it looks like. The argument is
  a design one. In place, a body is pushed off the positions earlier-indexed bodies have
  *already been moved to* this tick, so the earliest spawn in a pile is the only one that sees
  the pile as it really was and the whole crowd leans the way the serials run. Accumulating
  makes the push a property of the configuration rather than of arrival order, which is what
  the Belts' downstream-first order and the Machine port cursor's canonical order are each
  careful about. Integer addition is exact and commutative, so the total a body receives does
  not depend on which pair was summed first either.
- **It adds no state at all.** The two accumulators are per-tick scratch, zero at every point
  a hash is taken, in the same category as `_player_repair_credit` and the `FIRE` flag — so
  there is no new array to hash, nothing for `RunSave` to carry, no Enemy class, no node and
  no allocation per Enemy. The positions it writes were hashed already.
- **And no new tuning key.** The room a pair needs is `_enemy_hit_radius`, which is the one
  authority on how big a kind is and the very number `WorldView` scales the drawn body by — so
  **the Enemies a player sees not overlapping are the Enemies that do not overlap**, and a
  kind's size cannot be tuned for the look without moving what it collides with. That coupling
  is #49's and it is deliberate.
- **A Siege Hulk does not take part, and that is a design decision rather than an
  optimisation.** It halts the moment anything is inside `siege_hulk.range_metres` and that
  stand-off *is* its reach, so shoving it would be a second opinion about where it comes to
  rest — and it would let a crowd rotate the one Enemy whose facing carries a rule, the
  armoured front `_armoured` reads. Two Hulks are also not a crowd: what the user was
  complaining about is Chaff interpenetrating, and the boss is the kind a player meets alone.
  A Crawler walking through one is the price, and it is cheap.
- **An Enemy that arrived this tick is in the buckets and is not moved**, so the crowd already
  standing on the Breach gets out of its way before it takes its first step — the rule that it
  does not act on the tick it came through, kept rather than excepted.
- **Per-individual speed variation was deliberately not built, and the lever is recorded so
  that it is a decision rather than an omission.** #76's title names it and its acceptance
  criteria do not, which is the right reading: separation is what the user complained about
  and a crowd that is correctly spaced is most of the look. What it would cost is out of
  proportion to that — an amplitude is a feel number with **no existing authority to derive
  it from**, unlike every other number in this section, so it needs a real key in
  `content/tuning.toml`, which drags in a `--adopt-defaults` re-baseline and a second balance
  pass that would leave two mechanics tangled in one table. One attributable measurement beats
  two muddled ones. The shape, when somebody wants it: `[enemy] speed_variation_percent`, an
  offset of `serial % (2n + 1) - n` applied in `_enemy_step_metres`, which costs the Run no
  RNG draw for the reason `game/enemy_animator.gd` already de-locksteps a crowd off the
  serial.

#### Three things the measurements contradicted, and the first is the ticket's real discovery

Every one of these was reasoned out first, shipped into a probe, and found wrong by reading
numbers. They are the ticket's real content.

1. **The game was already producing the rank the user complained about, and no amount of
   separation would have fixed it.** `_advance_enemy` gathered every body onto the **exact
   centre line** of its lane, by up to a whole tick's travel — which is the same per-tick
   budget separation has. So the pass was measurably working and being undone every tick: a
   pair pushed apart across the lane was pulled back together on the next one and settled
   **5 cm apart against the 1.2 m their two bodies ask for**. *"The swarm arrives as a rank"*
   was therefore not a missing feature at all; it was an existing behaviour actively making a
   rank, and the user's one complaint was two faults wearing one coat. Nothing in the old
   behaviour could have revealed it, because with nothing pushing sideways there was nothing
   for the centring to undo.

   So **a lane is a lane and not a line**: a body is gathered back towards the middle only
   once it is further out than two of its own bodies, which is the distance at which it has
   stopped walking down the lane and started walking beside it. Derived from the radius, so
   still no new key — and a kind that does not separate keeps the old centimetre-exact
   behaviour, which is what leaves the Siege Hulk's walk in and #16's stand-off where they
   were.
2. **"No further than it walks" is the obvious bound and it deadlocks.** A pair that overlaps
   wants half the overlap each, which in a queue is more than a tick's travel for everybody in
   it — so the clamp handed every body a full step of push and **the rear of a queue was pushed
   backwards exactly as fast as it walked forwards**. Four of eight Crawlers stood still for
   the whole Run, which on screen reads as a hang and not as crowding. **Separation has to be
   weaker than walking**, and it is: half a tick's travel, so walking wins by a factor of two
   whatever the crowd is doing.
3. **Rationing the sideways step is the same mistake pointed the other way.** With the whole
   displacement bounded at half a step, a queue in a 2 m lane plateaued at **78%** of the room
   its own bodies asked for and stayed there — because sideways was the one direction that
   could have resolved the overlap, and it was being rationed as if it competed with the walk.
   It competes with nothing: stepping out of a crowd costs a body no ground. So the push is
   **decomposed** — with the march, half a step; across it, a whole one; and an Enemy that is
   not marching at all is not rationed, which is the common case in the one place a crowd is
   thickest. The decomposition is free, which is what makes it affordable: a march is always
   along one of the flowfield's four directions, so "with it" and "across it" is a choice
   between two numbers rather than a projection onto a vector.

#### What it actually does, measured

A crowd with road ahead of it converges to **exactly tangency — two fixed-point units, about
30 µm, inside touching — and holds there** rather than oscillating, from about four seconds
after a stacked release. A crowd pressed against the Nest settles at **0.82** of the room it
would like, and that is correct rather than a shortfall: eight bodies 1.2 m wide cannot stand
abreast on one lane, a bottleneck compresses, and a crowd that stopped pressing would be a
crowd that had given up on the Nest. What never happens in either regime is two Enemies at one
coordinate, which is the user's complaint stated exactly, and
`tests/cases/test_enemy_separation.gd` asserts it on **every tick** of a Wave rather than at
the end of one.

Two of that file's nine tests are the locality claim, because the algorithm is not visible
through the façade and must not be: a Crawler with nobody inside its own width advances by
exactly one tick of walking to the fixed-point unit, and a pair held at touching distance
**across a tile boundary** is found — which is the bug the bucketing could silently
reintroduce, since a search that looked only inside one cell would separate a crowd that
happened to share a tile and quietly stop separating one that did not.

#### What it costs, and the one case where the bucketing does not save you

Measured with `tools/visual/enemy_tick_cost.gd`, which times **`Simulation.step`** where
`frame_cost.gd` times `WorldView.sync`, against the same scenario with the pass and with the
pre-#76 Simulation. A 16.67 ms frame is the budget.

| Enemies | step, before | step, with separation | separation adds |
|---|---|---|---|
| 24 | 0.230 ms | **0.437 ms** | +0.21 ms |
| 200 | 2.435 ms | **9.525 ms** | +7.1 ms |
| 1000 | 11.941 ms | **94.238 ms** | +82 ms |

**The honest reading is that the pass is linear in the number of Enemies and quadratic in the
*density* of a crush, and the harness measures the worst case of the second.** It reaches the
Chaff tier's numbers by taking the Factory away, so nothing kills anything and the entire Wave
ends up pressed against one 4x4 Nest — where the bucketing cannot help, because the bodies
genuinely *are* all one another's neighbours and a cell holds O(n) of them. The baseline column
is linear across the same three counts (5x the Enemies, 4.9x the time); the separation column
is not.

**That is not reachable from a shipped scenario, and the reason is worth knowing rather than
assuming.** The balance rows end with **15 to 32 Enemies at the gate**, because Turrets kill
and the population is set by the fight rather than by the harness — so the figure a played Run
actually pays is the first row, a fifth of a millisecond. The crush grows without bound here
only because walking beats separation by design (finding 1 above), so bodies compress until
something kills them, and nothing does.

**The constant factor was worth taking and the asymptotics were left alone.** Two changes, both
**bit-identical** rather than approximations — the radius is read once per Enemy instead of
twice per pair, and the rejection test inlines `Fixed.mul` as a shift, which is the same
integer because every product in it is a square or a product of two lengths and `floor_div`
differs from `>>` only for a negative numerator. 1000 Enemies went from 192.7 ms to 94.2 ms and
**every hash over a 4000-tick crush was unchanged**, which is what let the balance table above
stand rather than needing re-measuring. What would bound the crush properly is a cap on how
many neighbours one body is pushed by — the displacement is clamped to half a step whatever
contributed to it, so past a handful the extra pairs buy only direction — and that is a design
decision with a real cost to argue about rather than a tidy-up. **It is #77**, with the three
rows above, the two things that have to be decided (which neighbours, and what N is derived
from) and the warning that unlike the pass above it is **not** bit-identical, so it moves the
hash and the balance table has to be re-run.

**The pair is committed and it is the argument**, and getting a picture of it at all took a
preset that did not exist.
[`docs/images/swarm_separation_before.png`](docs/images/swarm_separation_before.png) against
[`_after`](docs/images/swarm_separation_after.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_wave_shot.gd tools/visual/shot.sh out.png "crush bare"
```

In the before, six Crawlers at the Nest's corner render as **one body** — what looks like a
single Crawler is the whole Chaff tier standing at one coordinate, which is the user's
complaint exactly and is the strongest statement of it anybody has produced. In the after they
are six, pressed into a ragged arc around the corner they are eating, touching and none inside
another.

**`swarm` could not have shown it, and that was checked rather than assumed** — the existing
preset renders *identically* with the pass on and off. The reason is worth keeping, because it
is also a fact about the game: a Wave trickles out of a Breach half a second apart, so a
Crawler at 3 m/s is already 1.5 m behind the one in front before anybody pushes anything, and
**a lane contains no crowd**. The crowd exists where the lane stops. So `crush` waits forty
seconds instead of seven, frames the press at the Nest, and looks **down** at it rather than
along — the first attempt stood on the lane at eye height and could not tell the two builds
apart, because separation is a fact about the plan and a camera at head height reads a crowd
as one silhouette behind another whether or not they are inside each other. That is #48's
fourth finding and #49's `triage` a third time: a vantage that cannot see its subject.

### Both facts about the Nest's box have one authority each, and #61 closed the second

`MapLayout.NEST_FOOTPRINT_TILES` is **the** authority on the Nest's footprint. The mesh
generator reads that constant (`machine_specs.structure_footprints`) and the `nest` row of
`content/machine_bodies.csv` leaves its footprint columns blank to defer, which is the
arrangement every Machine's row already has against `content/machines.csv`. Until #61 both
files said 4x4 and **nothing compared them**, because the footprint cross-check only covered
rows `machines.csv` declares — which the Nest never will, because it is not a Machine. That
is the one failure the footprint check exists for everywhere else: for a Machine a
disagreement is a roof a player falls through, and here it is the 4x4 a player respawns on
top of, that obstructs every Enemy route, and that every Belt in every scenario docks
against.

`machine_specs.footprint_authorities` is the merged view and the one place that knows which
file owns which footprint, so a refusal names `sim/map_layout.gd` for the Nest and
`content/machines.csv` for a Machine rather than sending somebody to edit a file that is not
the authority. The constant is parsed with a regex rather than imported, because nothing in
the asset pipeline runs GDScript — Blender's bundled Python reads that module — and **the
dependency runs one way: `tools/` reads `sim/`, and `sim/` has never heard of the asset
pipeline.** A renamed constant is an error naming the file, because resolving a missing
authority to a plausible default is the silence this closed; so is the Nest ever acquiring a
row in `machines.csv`, which is the same defect from the other direction.

**Both arms were seen to fire, which is the whole value of a cross-check.** With the row
restating 4x4 against a constant moved to 3, `machine_specs` refuses and names both files.
With the row *blank* there is nothing to disagree with and the generator correctly builds a
3x3 Nest — what catches that is
`test_generated_machines.RegeneratingFromTheDeclaration.test_reproduces_the_committed_meshes_byte_for_byte`,
which regenerated the mesh and found it no longer matched the committed bytes. So a
deferring row is covered by the stronger of the two instruments rather than by neither. The
fixtures supply **both** sides as literals and make the two numbers genuinely disagree,
which is the lesson the mark-height test taught: a cross-check whose only exercised case is
one where the rule is trivially true passes for tickets while the rule is broken.

Its **height** went the other way and was the pattern copied: #30 needed it in the
Simulation, so `nest.height_metres` is tuning the Simulation owns and the asset suite
cross-checks the `nest` row's `body_height_mm` against it by name — the same treatment
`belt.deck_height_metres` gets. A Belt's 1x1 is now the only footprint in
`machine_bodies.csv` with no authority anywhere else, and deliberately so: one tile wide is
what a Belt *is* (DESIGN.md), and the Simulation holds no constant to disagree with.

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
`WorldView._machine_roof` — the taller of the housing the Simulation collides against and the
body the renderer is drawing — plus `AMMUNITION_GAUGE_LIFT_METRES`. It used to come
from a `MACHINE_GAUGE_HEIGHT_METRES` set "taller than any housing in the content", which is a
second authority on how tall a Machine is: it detaches the bar from everything that is not the
tallest, and #41 was the result — a dry 2.0 m Turret wearing its red backing 2.1 m clear of its
own roof, read as a saturated red rectangle floating over the Factory with no owner. Red is
load-bearing here, so a red mark with nothing under it is worse than no mark. The lift also has
to stay under `STARVED_MARK_LIFT_METRES`, which hangs off the same roof, or the amber starved
tag draws straight through the middle of the bar; `test_world_view` asserts both bounds — and
since #50 it asserts them **on a Turret whose body is taller than its declaration**, which is
the only version of that assertion with any teeth. See below.

#### Every mark hangs off the drawn body, not the declared housing

**#41 bites in both directions, #48 found the other one by rendering, and #50 fixed it.**
`query_machine_height_metres` is the **housing** — what a player stands on, what a placeholder
box is sized from, what `_walk` collides against — and several generated bodies carry a
superstructure well above it. Measured by standing every Machine up and reading the drawn
mesh's own AABB:

| machine | housing | body drawn | amber starved tag was at | |
|---|---|---|---|---|
| `miner_mk1` | 1.80 | **8.24** | 3.00 | inside the derrick, by 5.2 m |
| `smelter_mk1` | 1.50 | **7.75** | 2.70 | inside the flue |
| `coal_miner_mk1` | 2.00 | **6.59** | 3.20 | inside |
| `steam_boiler_mk1` | 2.20 | **5.05** | 3.40 | inside |
| `ammo_press_mk1` | 2.00 | **4.14** | 3.20 | inside |
| `mg_turret_mk1` | 2.00 | 2.00 | 3.20 | ok |
| `repair_pylon_mk1` | 2.40 | 2.40 | 3.60 | ok |

So **five of the seven Machines wore their starved tag inside their own body**, and the two
that did not are exactly the two Turrets.

**Why it was never caught is the more interesting half, and it is a lesson about tests rather
than about marks.** The Ammunition gauge is only ever worn by a Turret;
`test_a_gauge_hangs_off_its_own_machines_roof_rather_than_a_fixed_height` pinned the gauge's
lift against the starved tag's, and it **passed while the rule was broken** — because the one
Machine class that wears both marks is the one class where the two numbers cannot disagree.
The test looked like it covered the rule and in fact covered only the case where the rule is
trivially true. It is worse than that: neither Turret has a `.glb` *at all*, so both draw a
placeholder box, and a placeholder box is sized **from the declaration** — the two numbers are
not merely equal by coincidence, they are equal by construction.

**The fix is `WorldView._machine_roof`**, which #48 added for its own three split marks: the
**max** of `query_machine_height_metres` and the drawn body's own AABB. The Simulation's figure
stays a floor and is never contradicted, the mesh is asked only about its own extent, and
neither is a constant — which is what keeps #41's rule rather than bending it. #50 pointed the
starved tag and the Ammunition gauge at it, so **all five marks a Machine can wear now measure
from one function.**

**Three heights were rendered and the choice was made by looking, which is what the issue
asked for.** The pair is [`docs/images/marks_before.png`](docs/images/marks_before.png) and
[`_after`](docs/images/marks_after.png) — a starved Miner, Smelter and dry MG Turret in a row —
rebuilt with `SHOT_SCRIPT=tools/visual/compose_mark_shot.gd tools/visual/shot.sh out.png bare`.

1. **The declaration, which is what shipped.** The Miner's tag is a smudge inside the derrick's
   lattice and the Smelter's is **not visible at all**. Drawn, the right colour, in the right
   place horizontally, and invisible — which is why the count could never have found it.
2. **The housing plus a lift big enough to clear the tallest body in the content.** This is the
   `MACHINE_GAUGE_HEIGHT_METRES` #41 deleted, offered again because the issue listed it. It
   reproduces #41 exactly: the dry Turret's red backing floats at 8.94 m over a 2 m box with
   seven metres of empty sky under it. Rejected on sight, and worth having rendered — the
   argument for it is plausible on paper and the picture ends it in one glance.
3. **The drawn body, per Machine.** Each tag rests just above its own silhouette; the Turret's
   two marks do not move at all, because its body *is* its declaration. This is what shipped.

The worry the issue raised — that a tag 8 m up a derrick is attached but harder to read, being
far from the Machine's visual centre of mass — did not survive the render. At a player's
distance the tag sits on the derrick's cap with about a tag's height of gap, which reads as
resting on it; `STARVED_MARK_LIFT_METRES` is 1.2 m and the silhouette is directly underneath.
What would have been unreadable is candidate 2, where the gap is metres of nothing.

**#66 found the one case the third render could not show, and it is about the shape of the top
rather than about the height.** A tag rests a tag's height over the silhouette, which on a
Miner's wide derrick cap reads as resting on it — and on a Steam Boiler's **narrow chimney** is
1.2 m of open sky over a pipe. The lift was not moved; the tag was given a tether down to the
body, which is #52's answer to the same complaint. See "The floating yellow mark was the Steam
Boiler's starved tag, and it was in the right place", above.

**The assertion was rewritten so that it can fail**, which is the durable half of #50. It now
builds a Turret that **has a body** — a row borrowing `press_mk1`, which the repository already
carries at 2.4 m with a superstructure over it, under a declared 1.2 m housing — so the two
numbers genuinely differ, and it compares the gauge and the starved tag **where they were
actually drawn** rather than comparing two constants. Measured both ways while it was written:
with the gauge back on the declaration it fails by 3.2 m, and with only the starved tag back on
it the stacking clause fails with the tag at 2.4 m under a bar at 5.4 m. A second test,
`test_a_starved_tag_clears_the_body_a_player_can_see_not_the_housing_underneath_it`, pins the
tag alone on a starved Miner, where the gap is 5.2 m.

### Where the balance stands

**These figures are measured, not derived.** `tools/balance/measure.sh` plays scripted
sessions headless to the end of the Run and reports what happened; the whole method, the
scenarios and every finding live under "The joint balance pass", below. Re-run it after any
edit to `content/` rather than reasoning about what the edit did.

Shipped Map, shipped content, three seeds, measured 2026-10-09 **with #60 in** — and these four
figures have now survived #46, #47, #49, #58 and #60 unchanged, the last of them a full
re-derivation rather than a carry-forward. None of the four has a Machine with two Belts off it,
so #46 left them alone; their Belts were budgeted by #47's larger opening bill; #49's bigger
Breaker is a capsule only a *player's* round and a bite against a *player* ever read, which no
row here does; and #60 added rows rather than changing numbers. See "What a bigger Breaker cost
the table" and "What #60 measured".

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
the *other* side of the ledger: with the production line surviving, the stockpile peaks at 446
rounds around minute twenty-three and is still 96 deep when the Nest falls. (This read 454 at
minute twenty-four until #62 re-measured it; the 96 is exact.) **One Turret cannot
spend what one Press makes**, which is a different and better problem to have than the old one,
and it is why the second Turret in `fortified` is now a wash rather than a two-minute gain.

**The measured way past thirty minutes is to walk out and clear a Hive**, which is the only
thing in Milestone 1 that moves Heat permanently: `hive_sortie` is 32m05s against `competent`'s
28m48s, and it is the longest Run the harness has recorded.

**A second Ammo Press was the *arithmetic* answer to the middle of the Run, and #60 played it and
found it is a mistake.** `second_press` builds the Press *and* the second Turret the rounds would
go to — the pair this file had been calling for since #10 — and the Run is **24m14s, 16% shorter
than `competent`, ending with 416 rounds nobody could spend.** The arithmetic above is sound and
its conclusion does not follow: the Turret fires four rounds a second *while it has a target*, and
measured over a Run its two Turrets managed nineteen shots a minute, so **a Turret's output is
bounded by how long an Enemy spends inside its 16 m and not by its feed.** The Press's crafts are
still crafts, so the extra line bought Heat at 180 a minute against 180 a minute of decay and
brought the Waves four and a half minutes forward for rounds that sat on a shelf. "Production is
the defence" is still DESIGN.md's thesis and still how a Turret is fed at all; what is not true is
that *more* production converts into more killing on the shipped reach and rate of fire. See
finding 1 under "What #60 measured".

**#62 took that one step further and found a subtraction rather than a wash.** The open half of
#60's finding was the player's side — a player is not range-bound, so rounds a Turret cannot
spend ought to be rounds a player could. `armed_second_press` puts a rifleman on exactly
`second_press`'s Factory and is **14m43s, the shortest defended Run in the table, with the
player dry for 83% of it and 240 rounds stranded in a Factory that lost nothing at all.** The
second Press is fed by a 50/50 branch off the **one Smelter**, so it halves the first Press —
and the first Press is the only one whose rounds reach either the lane Turret or the Nest's
counter. One build therefore halves the gun holding the lane *and* the player's income, and
banks the surplus behind a second gun whose targets never arrive. **The second production line a
shooter needs starts at the ore, not at the Press.** See finding 3 under "What #62 measured".

The plate is buyable either way: the call-early lever pays `wave.call_early_bounty_per_item` of
each starting Item, and the Nest's store hands back whatever a Belt banked. `test_nest_store.gd`
proves that end to end; see the Nest's store, below.

Two things a later ticket should know:

- **A Machine's output buffer is uncapped**, so a Belt that fills up banks the surplus in the
  Ammo Press indefinitely. The stockpile a player builds between Waves is real and unbounded,
  and it is what carries the middle of the Run — it peaks at 446 rounds around minute
  twenty-three and is still 96 deep when the Nest falls.
- **A Turret on the Nest's lane now defends the Factory, and #34 is the whole of why.** A
  Breaker used to steer by the *Factory* flowfield from the moment it emerged, so it never
  walked into the reach of a Turret placed to cover the Nest — the `competent` Factory lost all
  five production Machines in its last minutes to a rule a player could not see. It now marches
  the Nest's own field until the Nest or a Machine is within
  `enemy.breaker_breaks_ranks_within_tiles`, so it arrives down the road, under fire, and turns
  on the Factory where a player can watch it. See the flowfield section, and "What #34 cost the
  table" below for the figures. The consequence for `fortified`'s second MG at (11, 6) is that
  it is no longer what answers the Breaker tier, and the two rows have converged.

## A shot you can see, and the one fact a query cannot report

#69, and the absence had been in plain sight since #10: grep `_sync_` in
`game/world_view.gd` and there were twenty-six of them, **not one of which drew a shot.** No
muzzle flash, no round in flight, no burst where it landed, nothing on the crosshair when it
connected. `query_turret_last_shot_tick` had existed since #10 and **nothing read it**, so a
Turret killing Crawlers four rounds a second was, on screen, a static box standing beside
Enemies that stopped existing — the one mechanic DESIGN.md's whole thesis rests on, and a
player could not watch it work.

That absence is also why the Ammunition gauge had to be invented. #10's own note says it: mid-
Wave a player is reading the whole Factory from thirty metres and needs to know which Turret is
about to stop. A gauge is a good answer to *which Turret is dry* and a poor substitute for
seeing the gun fire.

### A tick number is already an event, which is why most of this needs no memory at all

The line this ticket draws, and the reason most of it is free: **`query_turret_last_shot_tick`
reports *when* a Turret last fired rather than *that* it is firing.** A change already stated as
a number is not a condition anything has to diff — so "did this gun just go off" is a
subtraction against `query_tick`, and the muzzle flash needs nothing remembered between frames.
`query_player_last_shot_tick` is the same shape on the player's side.

Exactly one fact in a fight is not available that way, and it is the one the ticket is about.
**Where a round went and what it struck is known inside `_fight` and `_fire` and told to
nobody**: `query_enemy_health` reports what an Enemy's health *is*, and a round landing is a
change in it. A kill is worse than inaccessible — `_fire` removes an Enemy it reduced to nothing
in the same tick *and clears that serial off every Turret holding it* — so by the time anything
outside the façade can look there is no serial to resolve, no position to read and no health to
compare against.

**So `game/combat_events.gd` diffs, and the Simulation was not changed to tell it.** The honest
alternative is `_resolve_a_hit` recording what it did, and it was refused on the grounds #54
refused recording what killed a player: new hashed, saved, replayed state, in the Simulation,
bought for a mark on the screen. Nothing about the Run would change and `hash()` would.

It is also unnecessary, because the evidence is complete and **the precedent is literal rather
than analogous**: `game/audio_director.gd` has read exactly this since #21. It snapshots
`[health, attacking, position]` per Enemy serial, plays a death cue off a serial that has gone,
and already attributes a hit to a melee swing inside `MELEE_WINDOW_TICKS`. This file is that
design pointed at the picture instead of the sound, and the snapshot it holds is the same
category of thing — a reading on its way through, like `TickPump`'s leftover frame time, never a
fact about the world. `test_combat_events` asserts the consequence directly: four hundred ticks
with and without something watching leave the same state hash.

Four decisions in it worth knowing rather than rediscovering:

- **Attribution is evidence, not a guess, and the order is the design.** A Turret's claim on a
  hit is the serial it was aiming at **this frame or last** — last frame's answer is consulted
  because a killing shot clears its own target, which is the only reason `_turret_targets` is
  held at all. A player's trigger says only that a round left the barrel, since no query reports
  where it went, so the player takes the hits nothing else accounts for. A tick on which both
  fired therefore gives the hit to the Turret that was pointing at it.
- **A swing is a hit with nobody behind it.** A wrench, an Artillery Barrage and a Breaker's own
  bite all reduce health and none of them has a trajectory, so they are reported as
  `From.NOBODY` rather than forced into a third kind of shooter — and nothing draws a line of
  flight for one.
- **An attributed event carries its own shot's firing tick**, read back out of
  `query_turret_last_shot_tick` or `query_player_last_shot_tick`, so a mark's age is a Simulation
  quantity and not a reading of when a frame happened to look. An unattributed one is stamped
  with the last tick the Simulation executed, which is the renderer's own best reading and is
  exact whenever a frame stepped one tick. **Nothing `WorldView` draws is unattributed**, so the
  inexact case is unreachable from anything on screen; it is reported anyway because #70's
  subject is an Enemy's own body rather than who shot it.
- **The first observation of a Run reports nothing.** A Simulation resumed from a save has a
  Wave on the Map already, and diffing against an empty snapshot would read as every Enemy alive
  having just been hit. The consequence worth knowing is that a `WorldView` attached mid-Run
  draws no tracer for the round that was in flight when it attached.

### Three marks, one MultiMesh, and every duration a count of ticks

ADR 0001's case is exactly this one — fifty Turrets at four rounds a second plus a swarm of
bursts — so **no effect gets a node.** A flash and a burst are the unit box scaled evenly and a
tracer is the same box stretched along its own flight, which is what lets all three share one
buffer, one unshaded material and per-instance colour: the arrangement `_sync_ore_scanner`
already uses. `test_a_shot_is_never_a_node` asserts the scene tree does not grow by one over six
hundred ticks of firing.

- **The flash is at the muzzle of the body a player can see**, `_machine_roof` times a fraction,
  offset clear of the Machine's own footprint towards what is being shot at — #41's rule, and
  both of those numbers were settled by a render rather than reasoned (below). A Turret with
  nothing in its sights flashes over its own middle, which is the right answer for the one tick
  a target dies on.
- **`_mend` stamps the very same field `_fire` does**, so a Repair Pylon pulsing a plate would
  otherwise flash as though it were shooting; Pylons are excluded by name. The test that pins
  that puts a Breaker on the Map on purpose, because a Pylon with nothing to mend stamps nothing
  and the assertion would be the kind #50 warns about — a cross-check whose only exercised case
  is one where the rule is trivially true.
- **-1 is "has never fired" and needs a clause of its own**, or a Turret on tick 2 of a Run
  flashes for having been built.
- **`step` increments `_tick` last**, so the tick a shot was fired on is always one behind the
  tick anything outside the façade can ask about. **The freshest shot a renderer can observe is
  one tick old**, which is worth knowing before writing a test that waits for
  `last_shot_tick == tick` — one did, and it waited 1800 ticks through a Crawler being killed.
- **A missed round draws nothing out in the world, and that is deliberate rather than
  unfinished.** `_shoot` scatters the aim by an RNG draw before it resolves anything, so the
  direction a round actually took is not a quantity anything outside the façade holds — and a
  confident line down the player's *nominal* aim would be #35's green hologram over a click that
  did nothing, in a different costume. The lever, if misses ever want tracers, is the Simulation
  recording the scattered aim, and that is new hashed state and its own ticket.
- **The crosshair marks the player's own hit and nobody else's.** The events list carries a
  Turret's hits through the same channel, and a mark keyed on "something was hit" would
  congratulate a player for standing still beside a working Turret — a mark that says something
  false about their aim, which is worse than no mark.

**`query_player_eye_height_metres` is the only thing added behind the façade, and it carries no
state.** It is a projection over an expression that already existed inside `_shot_target`, and it
exists for the reason `query_player_facing` does (#52): the alternative is `game/` holding a
second copy of where a shot leaves from, free to disagree about the jump or about Survey View —
in the one place a player would read the disagreement as the gun being broken. `_eye_height` is
now the single definition and `query_player_camera_height_metres` reads it too.

### What the renders found, which is all of the geometry

The pairs are [`docs/images/gunfire_turret_before.png`](docs/images/gunfire_turret_before.png)
against [`_after`](docs/images/gunfire_turret_after.png) — the documented `competent` Factory at
**thirty metres**, on the tick its Turret fires — and
[`gunfire_hit_before.png`](docs/images/gunfire_hit_before.png) against
[`_after`](docs/images/gunfire_hit_after.png), the player's own round reaching a Crawler through
the player's own camera. Rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_gunfire_shot.gd tools/visual/shot.sh out.png "turret bare"
SHOT_SCRIPT=tools/visual/compose_gunfire_shot.gd tools/visual/shot.sh out.png "hit bare plain"
```

**The before images are the same Run at the same tick** — the composer reports "the Turret fired
on tick 2454" for both halves — which is what makes them an argument rather than two pictures: a
gun is firing, a round is reaching a Crawler, and nothing whatsoever on screen says so.

**`tools/visual/compose_gunfire_shot.gd` had to exist, and the reason is not the vantage.** A
Turret fires only while it holds a round *and* has something in reach, so a shot is a two-tick
window in a Run that has to have built a production chain first. Every other composer frames a
Factory standing still; `compose_wave_shot.gd` builds a Turret and never feeds it, so **its
Turret has never fired in any image this project has committed.** The loop is driven off the
Simulation's own queries rather than off the view, because the `before` half runs this same
composer against a `WorldView` that has none of #69's accessors — a loop that watched the drawing
could not take the picture that proves the drawing was missing.

Five findings, and every one of them is a number that was reasoned and wrong:

1. **The muzzle flash was *inside* the Turret**, which is #41's rule arriving from the
   horizontal direction. A constant 1.1 m reach from the footprint centre is well inside a 2x2
   Turret, whose footprint is four metres across; the mark was drawn, was the right colour, was
   at the right height and was invisible. `_muzzle_clearance` derives it from the footprint, for
   `_machine_roof`'s reason — a constant is right for one Machine and buries the mark inside
   every Machine bigger than that one.
2. **And then it was *behind* it.** At two thirds of the roof, 35 cm of horizontal clearance is
   not clear of a two-metre body seen from a camera forty degrees round from the line of fire.
   On the **roofline** the cube straddles the edge: half stands above the silhouette from any
   angle, and the half that overlaps the body is what gives the mark an owner, which is #52's
   rule about a bright mark with nothing under it.
3. **A seven-centimetre tracer is sub-pixel at thirty metres** — about two pixels of a
   1600-wide frame, at half alpha, which rendered as nothing at all. Sixteen is a round a player
   can see crossing a gap.
4. **One width cannot serve both kinds of tracer, and this is the sharpest of the five.** A
   Turret's round is seen from *outside* at tens of metres, where sixteen centimetres is a thin
   bright line. A player's own is seen **down its own axis from arm's length**, where the same
   rod is a slab a metre and a half across the middle of the frame, hiding the very thing it is
   about. So a player's round is thinner, starts a few metres out, and is offset to the weapon's
   own side — which is what makes it converge on the target from the lower right rather than
   point at the viewer, and is also what a real tracer looks like, since nobody sees one leave a
   barrel.
5. **A 0.75 m burst read as a cream crate standing among the Crawlers**, which is #56's finding
   about a red post that was the same size and nearly the same colour as the freight riding past
   it, in a different colour. Half a metre and hotter reads as a flash on a body.

A sixth is about the instrument rather than the marks, and it is #56's lesson again: **a camera
placed by arithmetic without a clause about the Nest** stood behind the four-by-four ziggurat,
which filled half the frame and left the Turret a hundred pixels wide on the far edge. A vantage
derived from the Simulation's own answers still has to be derived from the right ones.

And one the composer reported rather than drew: the first `turret` render printed **"the Turret
was destroyed before it fired"**, because a Wave called before the chain had smelted its first
plate ate the gun. Fed before hunted — which is also a fair statement of what a player who builds
a gun before a feed gets.

### What a still image cannot settle

Whether a three-tick tracer reads as a round or as a flicker, whether a nine-tick burst reads as
a hit or as a smudge, and whether a late Factory of several Turrets at four rounds a second is
legible or a light show. `MUZZLE_FLASH_TICKS`, `TRACER_TICKS`, `IMPACT_TICKS`, the two tracer
widths and the three colours are the levers, and every one of them is a constant in
`game/world_view.gd` rather than tuning, because the Simulation reads none of them — a tuning key
nothing in `sim/` reads is a key `Definitions` warns about, which is `BuildGun.REACH_METRES`' own
precedent.

### What #70 inherits

`CombatEvents` is a general record of what happened to an Enemy and not a record of shots:
`Kind.KILLED` carries the serial, the kind, the hit points of the blow that finished it and
**where the body was last seen alive**, which is the one fact nothing else in the project can
answer once `_remove_enemy` has closed the gap. It is reported whoever caused it, including for
a death nothing can be attributed to, and `MEMORY_TICKS` is a second — long enough for any mark
drawn off one. Nothing about it is tailored to a shot.

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
- **A Wall costs two plates a tile, out of `content/structures.csv`**, which is the table #47
  added to own a Belt's price and a Wall's together. It is deliberately *not* a tuning key, and
  the reason is the trap that stopped this being done sooner: a build cost names an Item, the
  Items that exist are exactly the ones the Recipes mention, and `machines.csv` is where a cost
  sits *next to* that check. A key in tuning would couple the tuning file to the Recipe table
  from the other side of the content directory, and it broke every test that supplies its own
  Recipes when it was tried. See "What a Belt and a Wall cost", below, for how the table avoids
  that.
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

**And `wall.health` is measured now, which took until #60 and turned up a structural answer
rather than a number.** A Wall is attacked by exactly one clause — an Enemy in a pocket it cannot
route out of — so a Wall a Wave can walk round is **never bitten at all**: `walled_lane` built
eleven tiles of funnel across the lane, lost none of them, and absorbed zero hit points over a
twenty-eight-minute Run. The only arrangement on the shipped Map that puts a Wall in front of a
tooth is sealing the one Breach, which `sealed_breach` does for eight plate: four Walls chewed
all the way through, **980 hit points absorbed**, and the Run two minutes *shorter* than
`competent` because the Wave is held fourteen tiles out, beyond the Turret's reach, and arrives
all at once. So 240 against 60 a second is a real relationship and it is not one a player meets
by building a maze. See finding 2 under "What #60 measured".

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

#### A roof is cover against what is shorter than it, and against nothing else

#58, and until it the reach was compared **horizontally**: `_player_in_contact` subtracted
positions on two axes and had never heard of `_player_y`, so a 1.6 m Crawler on the ground bit
a player standing on a 2.2 m Boiler. That was the conservative default rather than a decision,
and what made it worth settling is the section above — a player reaches 1.85 m, so their own
Factory is the staircase and they *will* be up there, with a Crawler at their ankles reading as
a bug whichever way the design went.

**Height counts now, and the rule is that a thing reaches as high as it is tall.**
`_enemy_player_vertical_reach` is `_enemy_hit_height` — the one authority on how big a kind is
and the very number `WorldView` scales the drawn body by — so **the thing that can reach you is
the thing you can see reaching**, and there is no second opinion, no new tuning key and no
table of multipliers. A kind is still four tuning keys and a `match` arm, and `_enemy_damage` is
still one number per kind whatever it is biting.

**What protects the keystone loop is not a ceiling anybody tuned; it is that the Breaker is the
tall one.** Measured against the declared heights:

| | reaches | so it can reach a player on | and cannot |
|---|---|---|---|
| Crawler | 1.60 | a Belt deck (0.9), a Smelter (1.5) | a Miner (1.8) and everything above |
| Breaker | 2.20 | a Miner, an Ammo Press, an MG Turret (2.0), a Boiler, a Silo (2.2) | a Repair Pylon or a Wall (2.4) |
| Siege Hulk | 3.20 | every roof `machines.csv` declares | — |

So **Chaff cannot reach a player on a production roof and the thing that actually takes a
Factory apart can**, which is DESIGN.md's own split — Chaff is the sense of threat, the Breaker
is the threat — arriving as geometry rather than as a sentence. And the free-safe-spot worry is
answered by a clause that was already there: a Breaker takes a **Machine** over a player
(`_enemy_contact_target`'s first clause), and a player on a roof is standing on a Machine, so
climbing one means watching it eat your floor. `test_roof_cover` plays exactly that — the
Boiler is chewed down at 60 a bite, the player falls on the next tick, and then they are an
ordinary person standing in front of a Breaker.

**Two tests rather than one three-dimensional distance**, and the split is the design. The
horizontal is a *tuned* reach, how far a thing leans; the vertical is *anatomy*, how high the
body goes. A single radius would conflate them, make `enemy.player_bite_reach_metres` silently
also a climbing allowance, and give the absurd result that getting nearer buys an Enemy height.
The vertical comparison is a single axis, so it needs no `Fixed.sqrt` and therefore none of the
squaring the rest of the file does to avoid one; the horizontal is squared exactly as before.
**No state was added** — the rule is a function of the kind and of `_player_y`, both of which
were hashed already.

Three consequences recorded rather than hidden:

- **A Wall and a Repair Pylon at 2.4 m are cover from everything but the boss.** A Wall is the
  one structure whose entire job is to stop something and #30 already put its top out of reach
  from the ground, so that is the right answer; the price of standing up there is that a wrench
  reaches nothing you climbed to protect.
- **Nothing reaches the Nest's 4.2 m crown, which is where `_respawn` puts a player.** That is
  the one perch whose own destruction ends the Run, so a player standing on it is losing slowly
  rather than safe — and `_a_shell_lands` is a blast radius that has never heard of `_player_y`
  either, deliberately: a roof is not cover from artillery.
- **A wrench's reach is still horizontal**, so a player on a roof can mend the Machine under
  them. On a 2.4 m Pylon that is a player holding one Breaker off indefinitely without being
  bitten — which is a marginal improvement on the trade hand repair already is (standing still,
  in the open, during a Wave, doing nothing else) and is left as it is. Extending
  `_within_wrench_reach` upward is a decision about repair, not about reach, and wants its own
  ticket.

**No measured figure moved**, and the null result is explained rather than merely reported: no
scenario in `tools/balance/measure.sh` puts a player above the ground, so `_player_y` is zero
in all nine and the new clause cannot fire. See "What roof cover cost the table", below.

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
  the Belt goes. **Since #47 the arrow is a promise the Simulation keeps**: a Belt docks against
  a declared port and nowhere else, so the dock tile the arrow stands on is literally the tile a
  Belt has to start on or end against. Until then it was a drawing of a rule nobody enforced.
  **Since #66 they are drawn only while the Build Gun is in hand and only around where it is
  pointing** — see "An arrow is advice, and advice nobody asked for is a hedge", below.
- **What is not connected is marked where it is not connected.** `query_belt_end_is_connected`
  and `query_belt_start_is_fed` are the geometry halves of `_hand_off` and `_load_from_port`,
  so a Belt drawn as connected is one that would really hand an Item over; a red post stands
  at every end that leads nowhere and an amber tag hangs over every Machine
  `query_machine_is_starved` calls starved. There is no stored connection to go stale, so
  demolishing the Smelter a Belt fed marks it on the next frame with no bookkeeping anywhere.
  An arrow a tile says which way each Belt carries. **Every one of those marks is a complaint,
  and #68 is the only one that is not** — see "Nothing said the line works", below.
- **The Machine picker is a grid of cells** — see "The hotbar states the chain" below, which
  is #53 replacing the flat row #36 shipped. Each cell still carries the key, the cost,
  whether a Delivery has it locked, and #20's generated icons, which nothing had used before
  #36. A Machine whose Recipe produces no Item — a Turret, a generator, a Silo — reads by the
  word for what it makes: a missing picture is an ordinary state, the rule a Machine with no
  generated body obeys. **Every Item the shipped Recipes mention has a picture since #59**,
  so that state is now reachable only by adding one — see "Every Item has a picture,
  and the gap cannot reopen", below.
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
  is told is to look at it. **`building_routing_before.png` sits beside them as #67's
  argument** — the same frame when the preview and the two HUD lines above it still
  contradicted one another; see "What colour a route is", above.
- **One objective line, and it is not a tutorial.** `game/objective.gd` is a pure function
  of the Run's state — place a Miner on a Node, place a Smelter, drag a Belt between them,
  deliver — with nothing to enter, nothing to skip and nothing remembered. A player who
  builds the line before reading it never sees a word of it; one who demolishes their Miner
  an hour in gets the first line back, because the first thing is true again. It goes quiet
  for good once a Delivery tier has landed. It names roles and states rather than Machine
  ids, because a line that named `smelter_mk1` would be a second content table written in
  GDScript. It lives in `game/` for the reason `BuildGun.refusal_text` does.

### An arrow is advice, and advice nobody asked for is a hedge

#66, and the evidence is one picture. The three building renders were rebuilt on the tip and
`running.png` — a player walking their own line with the Build Gun **holstered** — had its
whole mid-band filled with warm-orange quads at deck height, in front of the Belt and the
Machines they are about. **The Belt the arrows exist to help you lay was harder to see than
the arrows.** Two faults, and they wanted separate answers.

- **They were drawn when nobody was building.** Since #42 the weapon is the default hand, so
  the state a player spends most of a Run in was the state the whole Factory wore a hedge in.
  **`BuildGun.hand_refusal` is the one home for "is this player in a position to build"** and
  the arrows had never asked it — the same shape #35 found in the hologram, four inline checks
  on one side and none on the other. `_ports_are_advice_right_now` asks it and nothing else,
  so the rule has one home and the HUD panel, the hologram and the arrows cannot disagree
  about what is in a player's hands. Deliberately the **hand** and not the tool: the Machine
  tool is how a player decides which way round to turn the thing they are placing, which is a
  question entirely about ports, and the Belt tool is how they act on the answer.
- **At twelve to a Machine they had stopped saying "this tile".** Eight of the ten shipped
  Machines declare every tile of every face, so a square Smelter wears twelve arrows and the
  93-row table puts a ring around every Machine on the Map — and a ring pointing outward in
  all four directions carries no tile in it, which is the exact promise #47 declared the table
  tile by tile to keep. So arrows are drawn within `PORT_ARROW_RANGE_TILES` of what the Build
  Gun is asking about, which is where it is pointing **and**, with a drag in flight, the tile
  the drag was anchored on. That last clause is not a nicety: a route has two ends and the far
  one is the one a player committed to several seconds ago, so without it the arrow that
  started the drag goes out at the one moment it is being read.

**#47's tile-by-tile promise is kept in full and is not weakened by one word.** Nothing about
`content/machine_ports.csv` changed and nothing about what the Simulation enforces changed; a
Belt still docks against a declared port and nowhere else. What changed is *when* the
declaration is on screen — and around the aim, the same ring of twelve that read as a starburst
reads as a legend for the one Machine a player is deciding about, because they aimed at it.

**Four things the renders found, and the first is the one no test could have.**

1. **Filtered tile by tile, a Machine straddling the range shows half a ring.** The first
   implementation measured the range to each arrow's own dock tile, which is the obvious
   reading, and the render of it has the Miner beside the hologram wearing the arrows on its
   near face and none on its far one — **which reads as "those are all the ports it has"**, and
   is a worse thing to tell a player than nothing at all. So the range decides *which Machine
   is being asked about* and the answer is always that Machine's whole declaration.
   `test_a_machine_near_the_aim_wears_every_port_it_has_or_none_of_them` is the pin, built on a
   3x3 Smelter with one corner inside the range and the opposite one outside it.
2. **6 tiles, bracketed at 4, 6 and 9.** At 4 the Machine a player is placing *beside* loses
   its arrows — which is the one Machine whose output port they are lining the hologram up
   against, so 4 answers the wrong question. At 9 the picture on the opening line is identical
   to 6, so the extra reach buys nothing and only widens the band a late Factory draws a hedge
   in. 6 is a Belt run's worth of ground and about one Machine either side of the aim.
3. **`routing` did not change at all, and that is the control.** The drag is anchored at the
   Miner and aimed at the Smelter, so both wear their full rings and nothing else in the yard
   does — which is the picture the rule was designed to produce, arrived at without the
   composer being touched.
4. **The floating mark was not an arrow.** See below.

#### The floating yellow mark was the Steam Boiler's starved tag, and it was in the right place

The ticket reported "a lone yellow arrow in the sky at the right of frame with nothing visibly
under it" and asked for a diagnosis rather than a fix. It is **not an arrow and not a port
mark**: it is the amber `query_machine_is_starved` tag, over the Steam Boiler, which the Run in
that shot never gives any coal. Measured, standing the shot's own Factory up and reading the
buffers:

| | housing | body drawn | tag at |
|---|---|---|---|
| `steam_boiler_mk1` | 2.20 | **5.05** | 6.25 |

So it is exactly where #50 says it should be — `_machine_roof` plus `STARVED_MARK_LIFT_METRES`,
a tag's height over the silhouette — and taking the arrows away made it *more* conspicuous
rather than less, because it became the only loud thing in a calm frame.

**What #50's render could not see is the shape of the top it measures.** That ticket rendered a
posed row of a starved Miner, Smelter and dry Turret and judged the lift against a Miner's
derrick, whose **cap is wide**: a tag a tag's height over it reads as resting on it. A Steam
Boiler's body tops out in a **narrow chimney**, so the same 1.2 m is 1.2 m of open sky over a
pipe, and at the distance a player reads a Factory from the eye joins the tag to nothing. #41's
rule — a bright mark with nothing under it belongs to nobody — bites a fourth time, and the
lift is not what is wrong with it.

**So the fix says whose mark it is rather than moving it**, which is the answer #52 already
reached for an ore beacon floating over the ground: "the marking is also what gives the
floating stack an owner". A thin unshaded line in the tag's own colour spans the gap, from the
top of the body a player can see up to the tag resting over it. Three things about it worth
knowing:

- **Its length is `STARVED_MARK_LIFT_METRES` exactly**, so one mesh serves every Machine
  however tall — the gap it fills is the same gap everywhere by construction, and there is no
  per-instance scale to get wrong.
- **It is punctuation, not a second mark.** `STARVED_TETHER_THICKNESS_TILES` is 0.06, wide
  enough to survive a pixel at thirty metres and narrow enough that a Factory with six starved
  Machines is not six amber columns.
- **One tether per tag, asserted as a count rather than as a position.**
  `test_a_starved_tag_is_tethered_to_the_body_it_is_about` checks `starved_tether_count()`
  against `starved_marker_count()` and that the tether's middle lies between the drawn roof and
  the tag, so a tag that ever gets drawn without one fails rather than floats.

Rendered, the Boiler's tag now plants on its chimney and reads as a flag on a mast. **The
Ammunition gauge and the three split tags hang off the same `_machine_roof` and have the same
exposure on a narrow-topped body**, and they are deliberately untouched here: that is a
behaviour change to three shipped marks with assertions pinning them, which is exactly the
standing #48 gave the starved tag before #50 picked it up, and it wants the same treatment in
its own ticket.

### Nothing said the line works, and #68 is the one mark that is good news

Count what this game draws about a production line and every single item is a **complaint**: a
red post where a Belt leads nowhere (#36), an amber tag over a starved Machine (#36), a post at
a blocked branch (#48), a red post raised clear of the port arrows at a bad dock and two
sentences saying which rotation would fix it (#56). A player who has just laid their first
Miner-to-Smelter chain had to infer success from the **absence** of marks — and absence is
exactly what this project has twice found a player cannot read: #52's ore was invisible because
nothing marked it, and #41's gauge was unreadable because a mark with no owner says nothing.
"No red posts" is not a signal; it is the lack of one.

It is also the gap a live playtest walked into. The player built the opening line, the Smelter
ran, and their words were *"the smelter works but idk what next"*. **#71 fixed the instruction
that misled them** — see "The last step of the opening loop", below — and this is the half that
would have told them, without words, that the thing they had just built was alive. The two are
deliberately different registers: that one is a sentence telling a player what to do next, and
this one is the world acknowledging that they did it.

**It fires on a change and then stops, which is the whole of why it is not another hedge.** #66
landed an hour before this for exactly that failure on the port arrows — a mark that is always
on everything is wallpaper, and in that case it was hiding the Belts it was about. `LineWorks`
answers a *condition*, and the thing worth drawing is the **moment** it becomes true, which is
the distinction `game/audio_director.gd` has been built on since #21. So: when a chain first
reads whole a train of lights runs down its Belts and a tag stands over each of its Machines,
for `WorldView.LINE_WORKS_TICKS` — five seconds — and then the Factory goes back to being quiet.

#### What a chain is, and what makes one whole

`game/line_works.gd` is the whole of it, and it lives in `game/` for the reason `Objective` and
`BuildChain` do: whether a Belt hands an Item over is a fact the Simulation owns, and "these four
things are one line and it is running" is a sentence about those facts. The Simulation does not
know the file exists and asking any of it leaves `hash()` where it was.

A **chain** is a maximal group of Machines joined by Belt runs, plus the Nest if any run reaches
it — so a Miner belting ore straight to the counter is a chain with one Machine in it, which is
the opening Delivery and the first thing a Run is told to build. It is **whole** when:

- it joins at least two ends, so a Machine with no line is not a line;
- **every** Belt touching any of its Machines is fed at its entry and connected at its far end;
- every one of those Belts is **carrying at least one Item**, which is the literal content of
  "and carrying" and the one condition that makes this a statement about a line that is *running*
  rather than one that is merely wired up;
- and no Machine in it is starved.

The second of those is wider than it needs to be on purpose. A chain with a dangling Belt off one
of its Machines is a chain standing next to a red post, and **a positive signal must never
contradict a complaint** — so the dangling Belt breaks the claim even though it is not one of the
runs that joins anything. `test_a_chain_with_a_dangling_belt_off_one_of_its_machines_is_not_whole`
is that sentence as a test.

**`query_belt_is_stalled` is deliberately not consulted, which is #48's note read the other way
round.** A healthy saturated Belt feeding a slower consumer is stalled on most ticks — that is
what back-pressure *is* — so requiring "not stalled" would switch the signal off on exactly the
lines that are working hardest. #48 needed the stable fact because it was marking a *fault*; this
is marking a success and wants the opposite.

#### It is not a second opinion, and four projections are what make that true

Whatever says "connected" has to be the same thing that decides whether an Item really hands over,
or a line can read as working and starve. `query_belt_end_is_connected` already was that — the
geometry half of `_hand_off` — but it answered only *whether*, and walking a chain needs *what*.

So three projections, one line each over the function the hand-off itself goes through:
`query_belt_feeds_machine` over `_machine_a_belt_feeds`, `query_belt_feeds_belt` over
`_belt_downstream`, and `query_belt_feeds_the_nest` over `_hand_off`'s own Nest clause — which is
its own question rather than a case of the first, because the Nest is not a Machine and a Belt
docks anywhere on its 4x4 wall (GLOSSARY.md). **`query_belt_end_is_connected` is now literally
the disjunction of the three**, where it used to spell those three branches out a second time, so
there is one authority rather than four.

A fourth projection is about the *other* end. `query_belt_loaded_by_machine` is one line over
`_machine_behind_belt` — the function
`_load_from_port` asks and the one `_branch_belts` groups a Machine's branch by — so it and
`query_machine_branch_belt` are **the same answer read from the two ends**, which
`test_which_machine_loads_a_belt_is_the_branch_list_read_from_the_other_end` asserts rather than
assumes. It exists for cost as much as for symmetry: finding every Belt's loader off the branch
lists means walking every Machine's whole list, and each of those is itself a walk of every
Belt, where asking per Belt is one pass. `_sync_split_marks` already pays the quadratic version
every frame and this deliberately does not add a second one.

Nothing else behind the façade changed, which is why there is no new determinism fixture:
`test_declared_ports` and `test_belts` already replay the Factories this walks.

#### What it draws, and the one piece of memory in the renderer

Two marks and a tether, three MultiMeshes, and `test_the_signal_adds_no_node_per_belt_or_per_machine`
asserts the scene tree does not grow for any of them.

- **A train of lights down the Belts**, in flow order, at `LINE_WORKS_PULSE_TICKS_PER_TILE` — six
  ticks a tile, which is **faster than the goods on purpose**. A Belt carries one Item a tile
  every fifteen ticks, so the lights overtake the freight and read as a signal travelling the line
  rather than as more cargo. Only the lit ones are drawn and the train starts at the producer and
  runs out past the far end, which is the ore scanner's shape and for the scanner's reason: a full
  line of marks standing on a Belt is scenery, where a thing that *sweeps* reads as a signal.
- **A tag over each Machine in the chain**, off `_machine_roof` and the housing like every other
  mark since #50, one step above the split tag so the order is Ammunition gauge → starved tag →
  split tag → this. It cannot collide with the starved tag by construction — a chain is not whole
  while anything in it is starved — but a branch can be whole *and* splitting, so the split tag is
  a real neighbour. **Each tag is tethered to the body under it**, which is #66's answer to #41
  and which the first render said this needed too — see the renders below.

**`_line_works_since` is the only state in `WorldView` that is about the Run** — `_machine_roofs`
beside it is a cache of a fact about *content*, keyed by Machine id and thrown away on a reload —
**and it is the same category of thing as
`AudioDirector`'s snapshot and `TickPump`'s leftover frame time** — a reading on its way in, not a
fact about the world. It maps a chain's **geographic signature** to the tick it was first seen
whole. Geography and not indices, for the reason a Turret holds a serial: a Machine index shifts
the moment anything is destroyed, so a chain keyed by index would change identity because
something *else* fell over, where a Machine's anchor tile cannot move. Two consequences fall out
and both are right: a chain that stops being whole is **forgotten**, so mending a broken line is
acknowledged again; and a chain that gains a Machine has a new signature, so extending a line is
acknowledged too.

Everything drawn is a function of the tick minus that stamp, so nothing is timed by a clock and
nothing is drawn at random — `test_the_signal_is_timed_by_the_tick_so_a_frame_that_stepped_nothing_draws_the_same`
is the half of that rule a renderer can assert from inside.

**The HUD says `LINE RUNNING` for exactly as long as the marks are up**, counted off
`line_works_running_count()` rather than worked out a second way — the arrangement the
dangling-ends and split clauses already have, where the mark says *where* and the line says *how
many*. It sits beside the objective line on purpose: that one says what to do next and this one
says the last thing you were told to do is now running.

**No cue was added, and that is a decision rather than an omission.** The player has rejected four
separate attempts at sound in this project for being too loud, nothing in this repository can
listen, and a chain completing is the one event here whose *silence* costs nothing — the marks are
in the world, in the frame the player is already looking at. If it is ever wanted, the lever is a
`cues_for_frame` entry keyed on `line_works_running_count()` rising, which is a change and is what
`audio_director` is shaped to take.

#### What the four renders found

`tools/visual/compose_line_shot.gd` is a sibling of `compose_building_shot.gd` rather than a preset
on it, and the reason is `compose_death_shot.gd`'s: **the subject is a change, so the tool has to be
watching while it happens.** That composer builds its line, steps 240 ticks with nothing looking,
and only then syncs the view — fine for a shot of a condition and unable to photograph a signal
that fires on one frame. Everything here steps the Simulation with the view synced every tick.

```bash
SHOT_SCRIPT=tools/visual/compose_line_shot.gd tools/visual/shot.sh out.png "eye bare"
SHOT_SCRIPT=tools/visual/compose_line_shot.gd tools/visual/shot.sh out.png "survey bare"
SHOT_SCRIPT=tools/visual/compose_line_shot.gd tools/visual/shot.sh out.png "eye before bare"
```

The committed four are [`line_works_eye_before.png`](docs/images/line_works_eye_before.png)
against [`_after`](docs/images/line_works_eye_after.png) and
[`line_works_survey_before.png`](docs/images/line_works_survey_before.png) against
[`_after`](docs/images/line_works_survey_after.png). **`before` is honest rather than
reconstructed**: it watches the same Factory for longer than `LINE_WORKS_TICKS` and shoots after
the signal has subsided, so what comes out is the game as it shipped rather than a build with a
feature switched off.

1. **The before image is the argument, and it is worse than the ticket said.** The identical
   working line, and the only mark anywhere in frame is the **amber starved tag on the Steam
   Boiler** — which has no coal line in this Factory — with the only thing the HUD says about the
   Factory being `steam_boiler_mk1 starved`. So a player who has just got their first chain running
   is shown one complaint about something else and nothing at all about the thing they built.
2. **The tags floated with nothing under them, which is #41 biting for the fifth time and #66's
   specific shape.** A tag rests a tag's height over a *wide* cap — a Miner's derrick, which is
   what #50 judged the lift against — and **hangs** over a tapering one. The Miner's derrick and
   the Smelter's flue both taper to a point, so both tags read as marks in the sky. The lift is not
   what is wrong with it and was not moved; the fix is #66's own, a thin unshaded tether from the
   top of the drawn body up to the tag, taken on sight rather than rediscovered.
   `test_a_chain_tag_clears_the_body_a_player_can_see_not_the_housing_underneath_it` asserts the
   count and that each tether spans its own gap.
3. **Half-metre lights were modest at both distances and 0.75 m reads.** Bracketed by looking, like
   every other size in this file.
4. **The two vantages disagree, and in the opposite direction from #52's.** From the lift the
   **tags** are the strong mark — they are horizontal quads seen face on — and the lights are small
   squares among the deck's own flow arrows; at eye level the lights are the strong mark, reading as
   blocks running down the deck, and the tags are small against the sky. Each vantage is carried by
   a different half of the signal, which is the argument for having drawn two marks rather than one.
5. **Two findings in the tool, and the second is a fact about the game.** The first eye-level
   vantage stood across the line to the west, which is where the Steam Boiler stands — so the walk
   slid along it and finished somewhere else, the Miner's derrick filled the shot, and the Belt the
   picture is about was not in it. And **walking while surveying barely moves a player**:
   `_walk_to` steers by `_aim_at`, and from 26 m up the pitch it asks for is one the lift has
   pinned, so the aim never converges and the walk spends its whole budget turning. Walk first,
   then lift — the order is free, because where a player stands and how high they are looking from
   are independent.

#### The colour was measured, and the first one failed its own test

**#52's lesson is that the colours to check a mark against are the ones it is *guaranteed* to be
seen beside; #73's is that "guaranteed" has to be a number.** That ticket found the four Item
icons were four near-identical greys the moment somebody measured them, and it then gave cargo
four palette **materials** — so this mark's lights now run directly over `OxideRed`, `Soot`,
`DullBrass` and `WeldedSteel`, and its tag stands a metre above a **teal split tag** every time a
Machine is both whole and splitting.

The first value here was a pale mint, `Color(0.58, 1.0, 0.72)`, chosen the old way — by naming
the neighbours and observing that none of them was green. Measured in CIE Lab against every
colour it can share a frame with, it came out **ΔE 19.3 from the split teal and 17.4 from the
hologram**, against the **21.4** that separates #73's own closest *accepted* pair of cargo forms.
So the signal was nearer to the marks beside it than the four cargo colours are to each other,
which is the same defect #73 had just fixed one layer down.

The shipped green is `Color(0.36, 1.0, 0.22)`, and it clears that gate everywhere: 63 from the
split teal, 34 from the hologram, 42 from the cream flow arrow, 44 at worst from any cargo form,
67 from the amber starved tag.

**The sweep's actual maximum was not taken, and that is the point.** A saturated
`(0.2, 1.0, 0.0)` scores ΔE 73 and is a neon slab in a palette that runs 0.055 to 0.14 albedo —
which is #42's Wall, #52's ore and #64's brightened tool, three tickets this project has paid for
picking a colour against the wrong background. **Separation is a floor to clear, not a quantity
to maximise**, and the render is what says which side of that line a number is on. The after
images carry the Boiler's amber starved tag in the same frame, over #73's cargo on the same
deck, and nothing in them reads alike.

#### What it costs, and the cache a measurement forced

Measured with `tools/visual/frame_cost.sh` against the same scenario with and without the call,
on the 33-Machine, 9-Belt, 53-Wall Factory it builds: `WorldView.sync` goes from **11.64 ms to
13.60 ms**, so about **two milliseconds of a 16.67 ms frame** — roughly 1.4 ms deriving the
chains and 0.6 ms drawing the marks. That is the **worst case rather than the resting one**: it
is a Factory whose every Machine is inside a lit chain at once, which happens in the seconds
after a whole line comes up and not again, and past the window the derivation still runs while
nothing is drawn.

**It cost 3.6 ms before the measurement found where the first half of that was going, and the
answer was not in this ticket's own code.** `_machine_roof` ends in `Mesh.get_aabb()`, which
walks the merged body — and #48 and #50 only ever asked it for a Machine serving a **split**,
which is rare, where this asks it for **every** Machine of a working chain **every frame**. So
it is memoised by Machine id, which is what both halves of its answer are a property of: the
housing comes out of that Machine's row and the body out of the one `.glb` every Machine of
that id shares, so two Smelters cannot have different roofs. The cache is thrown away whenever
`query_definition_digest` moves, because `height_metres` is hot-reloadable and a cached roof is
exactly the kind of thing that would go on quietly answering with the number the Run stopped
playing by. Every mark in the file got faster, not only this one.

**It is shared machinery, so the key is worth stating exactly.** `_machine_roof` is read by five
marks — the Ammunition gauge, the starved tag, its tether, the three split tags and this one —
and the failure a cache over it could produce is a mark that is correct for the Machine that
*used to be* on that tile, which is precisely the class #41 and #50 each paid for. It cannot
happen, because **both halves of the answer are properties of the Machine's id and of nothing
else**: the housing is `height_metres` off that id's row, and the body is `_body(id)`, one Mesh
shared by every Machine of that id. Rotation is applied to the **node** rather than to the mesh,
so a turned Machine reads the same AABB; a placeholder has no `res://` path at all and falls back
to the declaration. Nothing index-shaped, nothing tile-shaped and nothing rotation-shaped is in
either the key or the value, so `_remove_machine` closing a gap cannot produce a stale roof — and
a mesh that is not loaded yet short-circuits **before** the cache is written rather than freezing
a null answer into it.

Two tests rather than a paragraph, because this is the kind of claim that passes for tickets
while being wrong. `test_the_roof_a_mark_hangs_off_follows_the_machine_and_not_the_index` stands
an 8.2 m Miner at index 0 and a 2.0 m Turret at index 1, demolishes the Miner so the Turret slides
down to index 0, and asserts the Turret does not inherit the derrick.
`test_the_roof_cache_is_thrown_away_when_the_definitions_move` puts two Runs whose `height_metres`
differs in that column alone through **one** view and asserts the second answer follows the
content. Checked by neutering the `_machine_roofs.clear()`: the second goes red.

**Two milliseconds was taken rather than engineered away, and that is a decision.** Deriving
every few ticks instead of every frame would cut it by an order of magnitude and would mean
drawing from a cached chain whose Machine **indices** have shifted — `_remove_machine` closes
the gap — so a tag could stand over the wrong Machine for a quarter of a second. A mark in the
wrong place is the failure this whole area of the file is a record of (#41, #48, #50, #66), and
it is not worth buying a millisecond with.

**What no render can settle** is whether five seconds is the right length, and whether a Factory of
a dozen lines being extended one at a time reads as encouragement or as flicker. `LINE_WORKS_TICKS`
is the lever and it is a constant in `game/` rather than a tuning key, for the reason
`BuildGun.REACH_METRES` is: the Simulation does not read it, and a tuning key the Simulation does
not read is a key `Definitions` warns about.
### The last step of the opening loop told a player to do a thing the game cannot do

**#71, and it is the worst class of defect this project has shipped: not a missing feature, but
an instruction.** From a playtest of the Windows build, in the player's own words: *"its not
clear how to carry ingots to the nest... the smelter works but idk what next"*. They had built
the opening line, the Smelter was producing, and they were stuck at the step the game had just
told them to take. The line said, verbatim:

```
Carry ingots to the Nest and press F — delivering is how a Run gets better
```

**There is no way to carry ingots.** Grep `sim/simulation.gd` for hand transfers and there are
exactly two: `_apply_deliver_to_nest` spends out of a player's own pockets, and
`_apply_withdraw_from_nest` fills them from the Nest's store. Nothing anywhere moves goods out
of a Machine's output buffer into a player's hands — the only way a plate leaves a Smelter is a
Belt. So the line named an **act for which no Input Action exists**, in step four of four of the
only sequence this game ever teaches, and a player who cannot get past it has no route into
Delivery, Depth, Gear or Stratagems.

**And it was wrong about the goods as well as the verb, which is the half the report could not
see and the half worth remembering.** The ticket reasoned that the trap was self-confirming —
`player.starting_stock` is `iron_plate:110`, a Smelter makes `iron_plate`, so pressing `F` at the
Nest *would* deliver out of the opening stock and confirm the wrong mental model. Checked against
the content, it is worse than that: **`t01_munitions` wants `coal:20`**, and
`_apply_deliver_to_nest` iterates the open tier's goods and nothing else. So `F` with a pocketful
of plate is refused `NOTHING_TO_DELIVER` and does **nothing at all**. The line named an
impossible act in aid of an Item the counter was not waiting for, and the feedback for obeying it
exactly was silence.

**Why every claim in it was individually assertable and none of it was asserted.** `Objective`
is a pure function of the Run's state with nothing remembered, which is what makes it cheap to
test — and the suite tested the steps *one at a time*, so each one was checked for the words it
contained and never for whether obeying it got anywhere. `tests/cases/test_opening_loop.gd` is
the durable half of this ticket and it is the other shape: it reads `Objective.pointed_at` for
which cell the line is about and `Objective.line` for which act, does that, and asks again, until
`query_completed_deliveries()` is non-empty. **Nothing in it knows the sequence of steps** — so a
step naming an impossible act leaves the loop with nothing to do, and a step naming the wrong
Machine builds the wrong Machine. The one seam it does not drive is the aim, deliberately:
`test_recorded_session.gd` is the fixture that proves a mouse reaches a tile, and this one
substitutes *the very query the step's own wording is derived from* —
`query_nearest_workable_node` is where "on the iron ore 12 m behind you" comes from — so the tile
a step is obeyed at is the tile the step named.

**One step became two, because the fixes are two.**

- **`Step.PRODUCE`** — the open tier wants an Item nothing in the Factory makes.
  *"Place a Coal Miner Mk1 — key 5; the Nest wants 20 coal to pay for your first Delivery"*.
- **`Step.DELIVER`** — something makes it and nothing is carrying it over.
  *"Drag a Belt from an orange arrow into the Nest — it wants 20 coal"*, behind the Belt-tool
  clause when the tool is not already out.

A single step could only ever have named one of those, which is how it came to name an act that
is neither.

Four things worth knowing rather than rediscovering:

- **The bill is read off `query_delivery_goods` and never written down.** A sentence naming a
  good is a sentence that has to come out of the tier, or it is a second copy of
  `content/deliveries.csv` in GDScript — which is exactly what "ingots" was. The count is what
  is **outstanding** rather than what the tier asked for, so a bill half paid by a Belt already
  running says so. The *first* outstanding good rather than all of them, because one line is one
  act: a tier wanting plate and Ammunition is two Machines and two Belts, and the second arrives
  by itself when the first is satisfied, which is how every other step here moves on.
- **`BuildChain.first_unlocked_producer_of` is `first_unlocked_of_role`'s sibling, and a role
  could not have answered this.** Coal and ore are both mined, plate and Ammunition are both
  crafted, and what separates the Machine a player needs from the one beside it is the Item it
  puts out. So this is the **one step that prints a display name** — read off `Definitions` for
  the row the chain chose, exactly as a picker cell reads it, with no id spelled anywhere in
  `objective.gd`. The lock is asked of the Simulation for `first_unlocked_of_role`'s reason: a
  player must not be pointed at a cell a Delivery still has shut.
- **The Nest has no arrow to aim at, so the sentence does not promise one.** The Nest is
  deliberately not port-enforced (#47) — it is not a Machine, so a Belt docks anywhere on its 4x4
  wall — and `Step.BELT`'s wording is *"drag from the orange arrow to the blue one"*. Reusing it
  would have sent a player hunting a mark the renderer never draws, so the new sentence names the
  orange arrow at the end that has one and says "into the Nest" at the end that does not. What
  **is** reused is the machinery: `_with_the_belt_tool` took the drag sentence as an argument
  (it was #67's, with the sentence baked in), because the two drags are different acts and the
  key clause in front of them is the same fact about the same hand — and two copies of that
  clause is how a tool comes to be named while it is already out.
- **`query_belt_ends_at_the_nest` is one line over the clause `query_belt_end_is_connected`
  already answers through**, the arrangement `query_node_yields_for` and
  `query_node_is_within_depth_of` have: the rule stays the Simulation's and `game/` does not
  learn it. Deliberately narrower than `query_belt_end_is_connected` — a Belt into a *Machine* is
  connected and is not a Delivery. It exists because the step has to **stop asking** once a Belt
  is in: the tier takes thirty seconds to fill, and a line still saying "run a Belt into the
  Nest" for all of it is #67's defect in the step rather than in the wording.

**What this ticket deliberately did not build, and the argument is filed rather than lost.** The
mechanic the player reached for is real — they did not say "I did not know a Belt could do that",
they said "I do not know how to carry" — and most of its shape already exists:
`aimed_tile_at_height` is the wrench's aim at a Machine's *body*, `_within_wrench_reach` is the
reach, `query_withdraw_refusal` is the shape of the refusal, and `_refund_machine` already moves
an output buffer into a player's pockets on a demolish. It was still not built here, because a
false instruction must not stay in the game while somebody debates whether to invent a verb — and
because the mechanic **competes with the Belt as the answer to the same problem**. `t01_munitions`
is twenty coal, which is three trips on foot, and `content/deliveries.csv`'s own comment says the
first thing a player should do is *"run a Belt out of the coal Miner and into the Nest and watch
the Factory pay for its own progression"*. A faucet that bypasses Belts for small amounts teaches
a new player they do not need one yet, at the moment it is cheapest to learn. **#72 took that decision and the answer was no**, with the
Nest's own legibility built in its place — since a player who has learnt to aim a Belt at an arrow
had nothing to aim at when the target is the Nest. See "No hand hauling, and the Nest says where
goods go instead", below.

**And it turned up a live defect in the step above it, which was filed rather than patched and
is now fixed.** `Objective._anything_is_starved` asked `query_machine_is_starved`, so a player who
had built the line correctly was told "Something is starved" on some ticks and what to do next on
the others — advice naming a fix already applied, which is the defect `_with_the_build_gun` and
`_with_the_belt_tool` exist to prevent for keys, in the step rather than in the wording. It was
pre-existing and it was not what #71 was opened about, so what it cost *here* was a named fixture,
`test_building_view._settle_until_nothing_is_starved`, which stepped a Factory until the step above
was satisfied and failed if that never came. **#74 is the fix and that fixture is gone**; see
"Why the right answer to one question is the wrong answer to another", below.

**The pair is committed and it is the argument.**
[`docs/images/opening_delivery_before.png`](docs/images/opening_delivery_before.png) against
[`_after`](docs/images/opening_delivery_after.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png "delivering bare"
```

`delivering` is #71's preset and it exists for the reason `opening` is #55's: **none of the
others can see the question.** `running` builds exactly the Factory the report describes and then
holsters the Build Gun, because that preset is a picture of a Factory working — and worse, it
cannot be trusted to show this step at all, because of the starved flicker above: the step before
it wins on some ticks and not others, and a render of a coin flip is not a render of a step. So
`delivering` frames `running`'s own Factory, keeps the gun out so the lit cell and the line
naming the same thing is half the subject, and then **steps until the line is the step**, bounded,
printing the line it is looking at if the budget runs out. The stop condition is kept after #74
rather than being taken out as redundant: what it waits for is a *step*, and the Factory in front
of it still has to get there. That is the same closed loop over the
real state that `_put_the_crosshair_on` already is, and it is what stops this picture being one a
tool can no longer reproduce — which is the failure #53 caught in this very script.

**And the first render of it found something about the shots that already exist.** `delivering`
started as `running` plus a stop condition, and it ran its whole 600-tick budget and gave up —
because `running` stands a Steam Boiler up to keep the grid off its baseline and **nothing ever
feeds it coal**, so that Boiler is *permanently* starved and `Step.UNSTARVE` wins on every tick.
The objective line in every committed building shot has therefore read "Something is starved"
since the Boiler was added, about a Factory whose only fault is the one the shot put there. The
way round it was not to fake state: a Miner and a Smelter alone draw exactly
`power.baseline_supply_kw`, so `delivering` builds no Boiler, the line runs unthrottled, the
Smelter's input buffer fills, and nothing is starved at all — which is the Factory the playtest
report actually describes.

**#74 did not make that render's problem go away, and that is the right outcome.** A Boiler
nothing feeds coal is starved *and* has nothing docked into a declared input port, so it raises
the step after the fix exactly as it did before — which is the step telling the truth rather than
flickering. The two faults in that paragraph were always separable: one was a working line
reported as broken, and the other is a Factory with a genuinely unfed Machine in it. `delivering`
builds no Boiler for the second reason, which is unchanged.

### Why the right answer to one question is the wrong answer to another

#74, and the durable half of it is not about this step. `query_machine_is_starved` is **correct**
and was not touched: it is `not _machine_has_its_inputs`, it is what `_machine_would_work` consults
so the Power grid bills nothing for a Machine that cannot work, and it is what the amber tag over a
Machine means. Several suites assert it. The defect was that `Objective` asked it a question it
does not answer.

The question the Simulation asks is **"would this Machine advance on this tick"**, which is a
fact about *now* and has to be, because the grid is read every tick. The question the objective
line asks is **"is something stuck"**, which is a fact about a *condition*. Those come apart on
exactly the Factory a player has built correctly: the shipped Smelter smelts two ore every 3.2 s
and the shipped Miner makes one every 1.5 s, so a saturated Smelter is empty-handed for the ticks
between consuming one craft's ore and holding the next craft's. `Step.UNSTARVE` is walked ahead of
the step below it, so the line alternated between "Something is starved — a Belt starts past an
output arrow and ends at an input" and what to do next, **about a line whose Belt starts past an
output arrow and ends at an input** — and the step it outranked is #71's, the one that pays for the
Run.

**The general shape, which is worth more than the fix:** a projection is a sentence about a
condition and the Simulation's own predicates are statements about a tick, so a `game/` file that
reads one as the other gets an answer that is true and useless. `AudioDirector` is the same
distinction already solved from the other side — "a sound is a *change* and a query reports a
*condition*", so it diffs query results against what they said last frame. `Objective` cannot diff,
because it is a pure function of the Run with nothing remembered; so it has to narrow the
*population* instead of widening the window.

**So the step fires for a Machine that is starved and has nothing docked into a declared input
port.** `Simulation.query_machine_is_fed` is the second half, and it is `_machine_a_belt_feeds` read
from the Machine's side — the exact shape `query_machine_branch_count` took for outputs in #48, one
clause of `_hand_off`'s own geometry asked per Machine rather than per Belt. So `game/` learns no
new rule, a Belt standing against a wall whose port runs the other way is **not a feed at all**
rather than a feed that delivers nothing (#47), and nothing behind the façade changed its
behaviour — which is why #74 left no new determinism fixture.

Four things worth knowing rather than rediscovering:

- **A Miner is why the *pair* is read and not the feed alone.** A Miner's input is the ground, so
  it declares no input port and `query_machine_is_fed` is false for one working its own Node and
  one on bare rock alike. Telling a player about a Miner on bare rock, over the wrong Resource, or
  on a seam deeper than its `max_depth` is this step earning its place — #52's three cases, all of
  them permanent — and any predicate that required a *missing Belt* would have thrown all three
  away. Read alone, either half is wrong about something; read together they are right about both.
- **Counting ticks was the other candidate and is refused by name.** "Starved for N ticks running"
  answers the same question and needs state in a file whose entire premise is that it has none:
  nothing entered, nothing skipped, nothing remembered, so a player who demolishes their Miner an
  hour in gets the first line back because the first thing is true again. A step that had to be
  *observed* for a second before it could be believed would be the first thing in `Objective` that
  a single frame could not answer.
- **The wording was left alone, and it is the one thing recorded rather than fixed.** The sentence
  names a Belt, which is the fix for a crafter and is not the fix for a Miner on bare rock — and
  the Miner is the case the step exists for. The ticket's own argument is that the wording matches
  this population exactly, which is true of the crafter half and not of the Miner half, so a
  second sentence split on the same `query_machine_is_fed` reading is the obvious next step. That
  is `Refusal`'s two-reasons-two-fixes shape (#56) pointed at a step, and it is a wording ticket.
- **The workaround it existed to force is gone.**
  `test_building_view._settle_until_nothing_is_starved` stepped a Factory until nothing was starved
  so that a fixture about the *last* step could stand on a tick where the one before it was quiet.
  Three fixtures called it and all three now stand on an ordinary tick. **A helper that exists to
  step past a flicker is evidence about the code and not about the test**, which is why #74's
  acceptance criteria named its deletion: a fix that left it necessary would not have been a fix.
  The assertion that replaces it is over a **window** of six hundred ticks rather than at one of
  them, because a single-tick assertion on an intermittent fault is a coin toss and is exactly how
  this shipped.

### No hand hauling, and the Nest says where goods go instead

**#72, and it is a decision before it is a mark.** #71 corrected a false instruction — the
objective line told a player to carry ingots to the Nest and there is no way to carry anything —
and left the evidence standing: the player's *mental model* was hand hauling and they reached
for it unprompted. *"its not clear how to carry ingots to the nest"* is not "I did not know a
Belt could do that". The ticket asked whether this game wants the verb, and the answer is **no**,
with the Nest's own legibility built in its place.

#### Why the verb is refused, in this project's own terms

The mechanic's shape was never in question — `aimed_tile_at_height` is the wrench's aim at a
Machine's body, `_within_wrench_reach` is the reach, `query_withdraw_refusal` is the shape of the
refusal, and `_refund_machine` already moves an output buffer into a player's pockets on a
demolish. It would have cost a `Kind`, a `Refusal` or two and, very likely, no new hashed state
at all. It is refused on four grounds and the first two are the load-bearing ones.

- **It is a second way to do a thing, and this project has consistently refused those.** There is
  no inserter entity (DESIGN.md). There is no build mode — `_player_build_mode` is a hand and the
  criterion is written as the absence of code. There is one Power grid and no topology. **A
  Machine's output leaves by a Belt** is the same kind of rule, and the cost of a second answer is
  not the code: it is that every later question about moving goods then has two answers that have
  to be kept in agreement, which is the disagreement `query_build_refusal` and `_dock_refusal`
  each exist to prevent one of.
- **It makes `t01_munitions` payable without a Factory.** The first tier is twenty coal, which is
  three trips on foot, and `content/deliveries.csv`'s own comment says the first thing a player
  should do is *"run a Belt out of the coal Miner and into the Nest and watch the Factory pay for
  its own progression"*. A faucet that bypasses Belts for small amounts teaches a new player they
  do not need one yet — **at the one moment in a Run when learning it is cheapest**, because the
  line is two Machines long and nothing is shooting at them. It is #60's `second_press` as a
  teaching problem rather than a balance one: the build that looks sensible is the one that
  quietly costs you the lesson.
- **Its own failure mode is the thing IRON NEST is most criticised for.** DESIGN.md is explicit
  that the line between satisfying friction and tedium is whether the machine answers you, and
  hauling twenty coal by hand is four round trips of nothing. The Silo's dial is the diegetic
  control this game wants: an irreversible commitment made once, under pressure. A hauling trip is
  transcription.
- **And the one thing it would genuinely have bought is bought more cheaply.** The honest case for
  it was that the opening is brittle — a Belt that will not dock is the commonest mistake there is
  (#47, #56) and a pickup is a way through that does not need the ports right first. But that is
  an argument about the Belt being hard to aim, and the answer to a hard-to-aim Belt is to make
  the target legible, not to add a route around it.

**What is being given up is real and is recorded rather than waved off.** A player reached for
this unprompted, in a playtest, and nothing here makes them right. There is no wrench-and-pockets
playstyle in the opening five minutes and there will not be one; a Factory that cannot run a Belt
produces nothing a player can hold. If a second playtest reaches for hauling again *after* the
mark below, that is evidence the decision is wrong rather than evidence the mark needs to be
bigger — and the thing to reach for then is #71's own filed argument, which is still intact.

#### The mark: four bands, one a wall, saying "anywhere along here"

**The Nest is deliberately not port-enforced (#47)** — it is not a Machine (GLOSSARY.md), so
`_hand_off` reaches it through a clause of its own and a Belt docks anywhere on its 4x4 wall. So
it carries no row anything draws and, until #72, **nothing marked it at all**. Every Machine in
the Factory wears arrows on every declared port; the one target the opening loop ends at wore
nothing, and a player who has learnt to aim a Belt at an arrow had nothing to aim at.

`WorldView._sync_nest_delivery_marks` is the whole of it: four bands, one a wall, each a
continuous run of chevrons pointing inward, at `PORT_MARKER_HEIGHT_METRES` — the Belt deck height
the port arrows already use, because a Belt really will end there.

- **Continuous, not one arrow a dock tile, and that is the entire design rather than a styling
  choice.** #47 declared the ports table tile by tile precisely so that *which tile a player aimed
  at* could never be the difference between a line that works and one that does not — so an arrow
  is a promise about **that tile**. The Nest's rule is weaker: any tile of any wall. A mark that
  claimed the stronger promise would be the renderer telling a player a rule the Simulation does
  not keep, which is #47's own complaint about the three tickets before it, inverted. Sixteen
  chevrons on sixteen dock tiles was the easy reuse and is exactly that mark.
- **The teeth are coprime with the footprint.** Five across a four-tile face, so no chevron lands
  on a tile boundary and no tile has one to itself — the geometry says "along here" rather than
  "here" even before the shape does.
- **It is drawn with the Build Gun in hand and nowhere else**, through
  `_ports_are_advice_right_now` — #66's one home for "is this player in a position to build", so
  the hologram, the HUD panel, the port arrows and this cannot disagree about what is in a
  player's hands. And it goes when the Run is over, because a fallen Nest is not a counter
  (`_nest_store_room` is zero and a withdrawal is refused) and a mark promising a hand-over there
  is a promise nobody can keep.
- **Placed off `query_nest_tile` and `query_nest_footprint`, never off a constant.**
  `MapLayout.NEST_FOOTPRINT_TILES` is the one authority on that square (#61) and a mark measured
  against a second copy of 4x4 is exactly the disagreement that cross-check exists to catch.
- **It is presentation and the Simulation never hears about it.** No new query, no new state, and
  `test_asking_where_goods_enter_the_nest_leaves_the_run_exactly_where_it_was` says so. One
  MultiMesh for all four bands, so the scene tree does not grow —
  `test_the_nests_delivery_marks_are_never_nodes_however_often_the_view_is_synced`.

#### The one rule that departs from the port arrows, and why

**`PORT_ARROW_RANGE_TILES` is deliberately not applied here.** #66's range is a **count**
argument: eight of the ten shipped Machines declare every tile of every face, so a Factory wearing
all of them at once is a hedge, and the fix is to draw the ring around the one Machine being asked
about. The Nest's count is **one**, for ever — four bands on a square that cannot multiply however
big the Factory gets — so the hedge this mark could form is four bands, which is not a hedge.

And filtering on the aim would answer the wrong player. **The mark exists for somebody who does
not know where to send their Belt**, and a mark that appears only once the gun is already pointed
at the right place is a mark only the player who already knew will ever see. It was implemented
with the range first, which is how that came out: it is invisible in exactly the frame #71's
playtest got stuck in. `test_the_nest_keeps_its_mark_wherever_the_build_gun_is_pointing` is the
rule, with the reason written next to it so nobody tidies it back into consistency.

#### What the renders found, and the candidate they threw away

The pair is [`docs/images/nest_delivery_before.png`](docs/images/nest_delivery_before.png) against
[`_after`](docs/images/nest_delivery_after.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png "nest bare"
```

**`nest` is #72's preset and it exists for the reason `triage`, `opening` and `delivering` do:
none of the others can see the subject.** Every building shot frames the opening line, which
stands twenty-odd metres east of the Nest — `delivering` renders #71's own step and **the Nest is
not in the frame at all**, which was checked rather than assumed. This one puts the crosshair on
the Nest's eastern dock ring with a route in flight anchored at the Smelter's output, which is
literally the drag the objective line asks for.

1. **A row of separate chevrons reads as sixteen arrows, however few of them there are.** The
   first implementation spaced five discrete arrowheads along each wall, and from Survey View the
   gaps between them were as wide as the teeth: what came out was a ring of discrete arrows round
   a square, which is a picture of a tile-by-tile declaration — the one thing this mark must not
   claim. **Continuity has to be in the geometry and not in the count.** The teeth share their
   edges now: one solid strip with a serrated leading edge, which reads as an apron.
2. **The colour was checked against what the frame guarantees, which is #48's and #52's finding
   both times.** It is the input ports' own cool blue, because it means the input ports' own thing
   and a player who learnt that off a Smelter has learnt it here; what says "not a declared port"
   is the shape. The frame this mark exists for is a Belt drag ending at the Nest, so what it is
   certainly beside is the route in flight (green, or red when refused), the cream flow arrows on
   it, and the warm orange output arrow at the far end. Rendered, it is the only cool thing in the
   picture and nothing in it reads alike. **A third colour was not taken**, for #67's reason: this
   game teaches as few colours as it can, and a new one to answer a question the existing pair
   already answers is a new thing to learn.
3. **It reads at both distances and differently at each**, which was checked by rendering the
   preset at eye level as well. From the lift the apron is a blue ring round a square and is what
   finds the Nest; standing at the wall it is a wide band at deck height on the face in front of
   you and is what says *this* wall will take it. Neither vantage carries the other, which is the
   argument for a band on every face rather than one mark.

#### What no render can settle

Whether a player who has never laid a Belt reads an inward chevron as "goods go in" rather than as
decoration — and whether four bands worn permanently by the Nest, for as long as the Build Gun is
out, read as a target or become wallpaper over a forty-hour Run. That second one is #66's own
question asked about a structure whose count is one, and the honest answer is that the count
argument makes a hedge impossible and says nothing about whether a player stops seeing it. The
lever if it does is the range this section argues against, and the argument against it should be
read again before anybody reaches for it.

### The hotbar states the chain

#53, and the complaint was the standing direction in one sentence: *"please simplify the
hotbar right now so I am CRYSTAL clear about what chain of buildings to build"*. #36's cells
were right and their **order** was `Definitions`' sorted id order, which puts the Ammo Press
first and the Miner fourth — a player reading left to right was shown the chain backwards.
Nothing was wrong with any cell; what was missing was the order, and the order was nowhere
to be read.

**`game/build_chain.gd` is the whole of it, and nothing in it is typed.** It lives in `game/`
for the reason `Objective` and `BuildGun.refusal_text` do: a Recipe's inputs are a fact and
"this is what you build after that" is a sentence about them. The Simulation does not know
the file exists, and asking any of it leaves the state hash where it was.

The order is derived from the one place the chain actually exists — a Machine's Recipe names
what it eats and what it makes, and `Definitions` interns both — out of three quantities:

- **A stage**: how many crafts deep a Machine sits. No inputs is stage 0, because a Miner's
  input is the ground; anything else is one past the deepest Item it eats. That is the
  **column**, and it is the sense in which column N feeds column N+1 — every Machine in a
  column eats something made in the one before it, *by construction*, which is what makes
  the arrow between two columns a true statement rather than a decoration. An arrow per
  *cell* would have claimed a Pylon feeds a Silo.
- **A reach**: how far downstream of a Machine the chain runs. Ore reaches the Turret three
  stages on; coal reaches the Boiler and stops. That sorts a column, and it is what puts the
  **main line along the top row** with the branches under it — derived, rather than somebody
  deciding which branch is the important one.
- **Whether a Delivery tier gates it**, through `Definitions.locks_machine` — read as
  *content* and not as Run state, deliberately. An order that moved when a Delivery landed
  would renumber the keys under a player who had just learnt them. What *this* Run has
  earned is still drawn, by the tint, every frame.

The shipped content comes out as a 2x4 grid with the gated Miners in a column of their own:

```
[1] Miner Mk1 → [2] Smelter Mk1 → [3] Ammo Press Mk1 → [4] MG Turret Mk1   [9] Miner Mk2
[5] Coal Miner  [6] Steam Boiler   [7] Repair Pylon     [8] Silo Mk1       [0] Miner Mk3
```

Five things worth knowing rather than rediscovering:

- **Keys are row-major over a column-major grid**, which is the one arrangement that gets
  both halves right. The grid has to be stages across so the chain reads left to right; the
  keys have to run along that top row first, so the line a player builds is `1 2 3 4`.
  Column-major keys would have handed the chain `1 5 7 9` and asked them to learn a lookup
  table. `BuildChain.key_label` is the single authority and the objective line reads it too,
  so the sentence and the cell print the same number.
- **The controller reads the same order**, so a key press lands on the Machine printed on
  the cell rather than on whatever sorts there by id. The number row is now the *only*
  picker — the wheel was given the hologram to turn in the ticket merged just before this
  one — which also un-did a workaround: `test_recorded_session` needed eight wheel steps to
  reach a crafter under id order and now simply presses `2`, because the Smelter is the
  second thing in the chain.
- **Ten keys is the whole of it, and nothing reaches an eleventh Machine.** The wheel used
  to; it does not any more. `Objective` says nothing about a key it cannot name rather than
  naming one that does not exist, and that is the clause to revisit on the day the Machine
  list outgrows the number row.
- **What a Delivery gates is a second group, past the end of the chain, and a render is why.**
  The deeper Miners are stage 0, which is where the chain says they go, and it made that
  column four cells tall — a hotbar is as tall as its tallest column, so two Machines nobody
  can build yet pushed the whole chain four rows up the screen and over the Factory it is
  about. That is also #53's "separate the opening line from everything else", arriving as a
  layout constraint rather than as a preference. The gap before that group is a plain
  separator, wider than an arrow: what separates the two is that there is no relationship.
- **A cell says what it eats as well as what it makes**, with an arrow between the two slots
  *inside* the cell. The arrow is not decoration either: `iron_plate` had no generated icon
  when #53 rendered this, so the Ammo Press (makes Ammunition) and the MG Turret (eats it)
  came out carrying one identical glyph each with nothing to say which side of the
  transformation it was on. #59 filled that slot and the arrow still earns its place — two
  pictures side by side say even less about direction than one does.
- **`Objective` and the hotbar cannot disagree, because there is one `_step` behind both.**
  `Objective.line` names the act and `Objective.pointed_at` names the cell, in the Build
  Gun's own selection space — a Machine's definition index, or `machine_count()` for the
  Belt, which is the convention `query_player_selected_machine_index` already uses. Which
  Miner and which Smelter is `BuildChain.first_unlocked_of_role`'s answer off the chain
  order, so nothing here names a row.

**What the renders found, which is the part that could not have been tested.** Four defects,
and the first two were in the tool:

1. **The `placing` and `routing` shots had been rendering with the Build Gun holstered since
   #42** — a Run opens holstered, the composer never drew it, so for several tickets the
   pictures of *the act of building* showed a player who cannot build and **no hotbar at
   all**. The committed `building_placing.png` was an older artifact the tool could no
   longer reproduce. `compose_building_shot.gd` now draws the Build Gun for both.
2. **The cells had no visible backing.** #36 drew the three states by modulating the default
   `PanelContainer` theme, which is a near-transparent near-black: measured off the shot,
   every cell was within a few counts of the ground behind it and the *lit* cell read as a
   darker box than its neighbours. The one new state #53 adds was invisible outright. The
   cells now own a `StyleBoxFlat` and the state is a **border colour**.
3. **Half-size icon slots read as smudges.** Two 20-pixel glyphs under a three-line caption
   are not two glyphs, and a cell is already as wide as "[6] Steam Boiler Mk1", so there was
   never any width to save.
4. **A pale green for "selected *and* next" was thrown away**, the way #52 threw away its
   first colour pair. The one frame where that state is common is a Belt drag, which already
   fills the screen with the green of a valid route — three greens in one shot. Selected
   wins instead, which is the better rule anyway: the cyan's job is to get a player to pick
   the cell, so a cell they have picked has had the advice.

**Two findings recorded rather than patched**, both out of this ticket's scope. **The
first is fixed; #55 is the ticket, and the section below is it.**

- ~~**A Run opens with the Ammo Press on the Build Gun.**~~ **Fixed by #55.**
  `_player_selected_machine` holds an id but it was *filled* from a scan of the sorted
  table, so a Run opened on `ammo_press_mk1` — the third thing in the chain — while the
  hotbar marked the Miner's cell and the objective line named its key. #53 left it for two
  reasons and both were right: fixing it moves `Simulation.hash()`, and "the first cell of
  the chain" is a `game/` concept `sim/` must not learn. What was wrong was the conclusion
  that those two made it unfixable. See "Where a Run opens, and who is allowed to know",
  below.
- ~~**`iron_plate` has no generated icon.**~~ **Fixed by #59**, and the gap is a suite
  failure now rather than a note. See "Every Item has a picture, and the gap cannot reopen",
  below.

### Every Item has a picture, and the gap cannot reopen

#59, and it is the smallest ticket in this file with the longest tail, because what it
actually fixes is a **class of silence**. The set of Items is exactly what
`content/recipes.csv` mentions and there is no Item table — which is the right design and
also means the content can grow an Item and leave the art behind with nothing anywhere
saying so. `iron_plate` did, for four tickets of the hotbar being worked on: #20 generated
ten icons against a speculative Item list, the shipped Recipes later interned a fourth Item
that was not on it, and the consequence was that **the Smelter's output slot and the Ammo
Press's input slot were both blank** — which are exactly the two cells a player reads to
learn the first production decision in the game.

**The icons are committed, and that is the fact to carry away.** `assets/generated/` is
*tracked*, unlike the weapon viewmodels, the audio cues and the set-dressing props: these
are SDXL output from prompts this project wrote, under CreativeML Open RAIL++-M, generated
locally by `tools/aigen/` from committed recipes. So a clone has all nineteen images, a
clone without the purchased packs sees **exactly what the author sees**, and an absent icon
is never "the quarantine is not linked". That is also why they are **not** in
`tools/assets/asset_staleness.py` and must not be: #57's rule is *where the output is
committed, prove it; where it is gitignored, date it*, and the proof is already available
and stronger — `generate.py --verify` regenerates from the committed settings and compares
pixels, and all nineteen come back **bit-identical** (0.000 mean levels) on this machine.

**The check is a Godot test rather than an asset-suite one, and the reason is not where the
art lives.** `tests/cases/test_item_icons.gd` walks `Definitions.item_ids()` through
`WorldView.icon_path_for_item` — the very function the cells call — and fails naming the
Item. Three things decide the suite:

- **The Item set has one authority.** A Python check would re-implement the interning
  against `recipes.csv`, which is a second opinion about the one thing this project is most
  careful to keep singular. Here it is `definitions.item_ids()`.
- **So does the resolution.** The gate and the hotbar cannot come to disagree about what
  resolves, which is the arrangement `query_build_refusal` has with the hologram.
  `_icon_of` is now one line over the public function the test calls.
- **`ResourceLoader.exists` asks a strictly stronger question than a file check**, and only
  the engine can ask it. A committed `.png` whose `.import` sidecar was *not* committed is
  present on disk and invisible to the game — a blank cell with the file sitting right
  there, and precisely what a Python `os.path.exists` would wave through.

**The icon itself is a stack, and that was decided by looking.** Nine candidates across
three wordings were swept into gitignored scratch, and every single-plate wording came back
as a flat square seen face on — which is `steel_plate`, already in the set, in a darker
grey. At 64px that is one icon drawn twice. A stack has thickness, a stepped outline and a
three-quarter read, and it is the truer picture of the Item anyway: plate is the bulk
material every build cost in the game is denominated in, not one bolted part.
`_contact_sheet.png` is where that judgement is made, because an icon set is judged as a
set and never one at a time.

**The pair is committed and it is the argument.**
[`docs/images/hotbar_chain_before.png`](docs/images/hotbar_chain_before.png) against
[`_after`](docs/images/hotbar_chain_after.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png "opening bare"
```

In the before, the chain **visibly breaks between cells 2 and 3**: the Smelter eats ore and
makes nothing, the Ammo Press eats nothing and makes Ammunition, and the one transformation
the opening line is entirely about is the one with no picture on either side of it. In the
after it reads ore → plate → ammunition → damage with every slot filled. `opening` is the
preset because it is the only one that builds nothing, selects nothing and walks nowhere —
#55 added it for exactly that, and `bare` is what keeps the purchased yard out of a picture
bound for a public repository.

**Regenerating the whole recipe is the right way to add one**, and it is its own proof: the
ten existing `.png` files came back **byte-identical** — `git status` listed only the new
icon, the rebuilt contact sheet and the manifest — so nothing was disturbed and the
reproducibility claim in `tools/aigen/README.md` was re-derived rather than trusted. The
contact sheet is only rebuilt when more than one icon is generated, which is the other
reason not to use `--only`. Two provenance fields on the ten unchanged records did move,
`seconds` and `recipe`; `Record.matches` compares **fingerprints** and is documented as
immune to a path change, and every `image_sha256` is untouched, so nothing a pixel depends
on differs.

### Where a Run opens, and who is allowed to know

#55. The Build Gun now opens pointed at the first Machine of the chain, and the way it gets
there is the point: **content is told where a Run starts, and nothing in `sim/` learns what a
chain is.**

`player.starting_machine` names a Machine **id**, and the precedent it copies in every
respect is `player.starting_weapon` — a tuning key naming a row, resolved by `Definitions`,
checked against the table it names *and* against the Delivery table, which is the
cross-table question that makes tuning the last thing read. An id rather than an index for
the reason the Build Gun has always *held* an id: a hot-reload that resorts the table must
not change what a Run opens pointed at.

Six things worth knowing rather than rediscovering:

- **`Simulation._opening_machine()` is a one-line read with no fallback, and the absence is
  deliberate.** It used to scan for the first unlocked Machine by id, and that scan was
  carrying a real guarantee — a Build Gun holding something the Simulation would refuse to
  place teaches a player the game is broken. The guarantee **moved** rather than being
  dropped: `_check_starting_machine` refuses a set naming no row or naming one a Delivery
  tier locks, and a set with any error carries no definitions at all. A fallback left in
  would be a second opinion about which Machine a Run opens on, in the one place a
  disagreement is invisible.
- **The two orders are put side by side in exactly one test, because that is the only place
  they can be.** `test_building_view.test_a_run_opens_pointed_at_the_first_cell_of_the_chain`
  asserts the hologram, the lit cell and the objective line all name the same Machine on tick
  0. The Simulation has no opinion about cell 0 and must not grow one, so nothing on the
  `sim/` side of the boundary could have asserted this.
- **It cost a cascade anyway, and the shape of it is the lesson.** A required tuning key that
  names a *row* is not the same risk as one that names a number: a file supplying its own
  `machines.csv` has no `miner_mk1`, so the set is an error and carries no definitions at
  all — the 156-failure shape #51 exists to prevent, arriving through a door `ContentFixture`
  does not cover, because these files replace the **table** rather than the tuning. Fifteen
  test files declare their own Machine table and **four of them name no shipped id**:
  `test_game_audio` (9 red), `test_machine_mortality` (3), `test_silo` (26) and `test_turrets`
  (8) — forty-six failures between them. Each now substitutes `starting_machine` beside the
  `starting_stock` it was already substituting, naming a row it does have.

  **What found them was grep, and grep found the wrong answer first.** Searching for
  `machines = ` found six files and all six were fine, which read as "no cascade" — and was
  simply the wrong query: four more files pass their table positionally to
  `Definitions.parse` and never write that assignment. Scanning for the *header string*
  inside every triple-quoted block in `tests/` is what actually enumerated them. **A key
  naming a row wants that scan, not a search for a variable name.**

  **Two files in the four also parse the shipped table elsewhere, and those sites must keep
  the shipped value** — `test_silo._fixture_content` and `test_turrets._content` /
  `_cannon_content`. The override is threaded next to the `AMMO_STOCK` / `STOCKED`
  substitution each site already does, which is what makes "this site brings its own
  Machines" and "this site gets the override" one decision rather than two.

- **`test_build_gun.gd` changed on purpose rather than under duress.** It names `press_mk1`,
  which sorts **last** of its three Machines, so its assertion fails if anything ever goes
  back to taking the first row by id. A fixture that happened to agree with both rules would
  have asserted nothing.

- **Eight tests went red for a reason that was not the key at all, and it is worth knowing
  about.** `test_godot_layer_smoke` (seven) and `test_belt_routing` (one) click and expect a
  Machine; they were relying on the opening selection being something placeable **anywhere**.
  A Run now opens on the Miner, and a Miner aimed at bare rock sends **no intent at all**,
  because the Build Gun snaps to a Node or points nowhere (#42). Every one of those tests is
  about the click rather than about the Miner, so each now names `ammo_press_mk1` — which is
  exactly what a Run opened on before #55, so they do what they always did and now say so.
  **The dependency was invisible until the default moved**, which is the argument for naming
  a fixture's premise even when the default happens to supply it.
- **No replay fixture needed re-recording.** The opening hash moves — the selection differs
  and the definition digest has a key more — but a `ReplayRecording` made without a
  `Definitions` re-reads `content/`, so record and replay move together and every fixture
  asserts `is_identical` rather than a literal hash. What *could* have moved is a fixture
  that built by clicking without selecting first; there is none, because
  `test_recorded_session` presses `2` for the Smelter (#53) and every other build fixture
  passes a definition index.

**The render is `opening`, a fourth preset on `compose_building_shot.gd`, and it exists
because none of the three could see the question.** `placing` puts a Smelter on the gun by
hand, which is precisely the act that makes the opening selection invisible — the same reason
#49 needed `triage` when `pair` and `distance` both framed past its subject. So `opening`
builds nothing, walks nowhere and selects nothing, refusing to improve the vantage the way
`compose_spawn_shot.gd` does, with one exception: a single `B`, which is the keypress the
objective line is itself telling the player to make and without which there is no Build Gun in
frame to be pointed at anything.

```bash
SHOT_SCRIPT=tools/visual/compose_building_shot.gd tools/visual/shot.sh out.png "opening bare"
```

**And the picture is the argument, as it was for #48 and #52.**
[`docs/images/opening_selection_before.png`](docs/images/opening_selection_before.png)
against [`_after`](docs/images/opening_selection_after.png). The before is a worse statement
of the bug than the issue was: the objective line says *"Place a Miner on the iron ore 12 m
behind you — key 1"*, the HUD says `build gun: ammo_press_mk1`, **two cells are lit in two
different colours** — cyan on the Miner for "next", amber on the Ammo Press for "selected" —
and the thing in front of the player is a **green, placeable Ammo Press**. Green means click
and it goes down, so the one element on screen that reads as an instruction was inviting a
new player to spend 14 of their 110 plate on the third Machine in the chain as the first act
of the Run. After: one cell lit, `build gun: miner_mk1`, and a Miner's derrick where the
hologram was.

The after shot's hologram is **red**, and that is #42 working rather than a defect left
behind: a Miner snaps to a Node or refuses, the player spawns facing away from the ore, and
the HUD says `no ore in range — a Miner has to stand on a Node` under a line that says the
ore is 12 m behind them. Turning to face it would have been exactly the improved vantage this
preset refuses — and the red version is the more useful picture, because it shows the
selection, the snap and the objective line all agreeing about the same Machine at once.

`bare` is new on this composer and the second reason for it is the licence: the yard is drawn
out of the **purchased** packs when they are linked, so a shot bound for `docs/images/` in a
public repository has to be able to leave them out.

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
`"iron_plate:110"` — the whole competent Factory costs 108, being 78 of Machines and 30 tiles
of Belt at a plate each — so **a Run opens with the opening
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

**The store is what arms a player, and #62 measured whether it keeps up.** #15 made firing
spend **Ammunition** out of these same pockets, and `player.starting_stock` is deliberately
still plate alone — so a Run opens able to build its line and swing a wrench and unable to fire
a shot. That is the keystone loop stated correctly rather than a gap, and it stays.

What #62 added is the measurement that had been open since: **the Nest's line pays a player
about nineteen rounds a minute, which is half of one Ammo Press, and that is enough to fight a
Wave out of and nowhere near enough to lean on a trigger with.** `armed_player` is dry for 9%
of the Run against `rifle_picket`'s 74% on the *same* income, so what a player can do with the
faucet is set by their trigger discipline and not by the store — whose cap of 200 was never
approached, peaking at 24. What it costs is 4m34s of Run and the lane Turret spending twice as
long empty. See "What #62 measured" under the joint balance pass, and the Gear section.

### What a Belt and a Wall cost

#47, and the half of it that is about the production loop rather than about the economy. The
length of a route is the number a player actually decides on, and it is on screen before the
drag is released — so a free Belt made layout a question of taste and a priced one makes it a
question of routing, which is the decision a factory game is about. A Wall was the cheapest
thing in the game at nothing at all.

**`content/structures.csv` is the table that owns both**, one row per thing that is built and is
not a Machine, with a `build_cost_per_tile` column in the same `item:count` form a Recipe's
inputs and a Machine's `build_cost` use. A Belt is a plate a tile and a Wall is two.

- **Neither is a row in `content/machines.csv`, and that was never in question.** DESIGN.md
  lists both alongside the Nest, outside the eight Machines, and GLOSSARY.md keeps the words
  apart. A structure has no Recipe, no Power, no ports, no buffers and no role, so the only
  thing a table has to say about one is what it costs — which is exactly what
  `StructureDefinition` carries and all it carries.
- **The set of structures is closed, which is the opposite of the Machine table and is right.**
  A ninth Machine is a row; a third structure would need a `BUILD_*` intent, so a row for one
  would be a number nothing reads. The loader therefore refuses a row naming anything but
  `belt` and `wall`, and refuses a file that omits either.
- **How the naming trap was solved, because it is why this had not been done.** A build cost
  names an Item, the Items that exist are exactly the ones the Recipes mention, and
  `machines.csv` is where a cost already sits *next to* that check. A key in
  `content/tuning.toml` would couple the tuning file to the Recipe table from the other side of
  the content directory — and it broke every test that supplies its own Recipes when it was
  tried, because such a test's Recipes do not mention `iron_plate`, so a tuning value that did
  would make its whole definition set an error and carry no definitions at all. The table fixes
  that in two moves. It is **read after the Recipes and checked against them** by
  `_check_structures_against_recipes`, which is `_check_machines_against_recipes` pointed at the
  other table. And **a caller that supplies no structures source gets structures that are
  free**, which is not a default smuggled in: it is the same thing an empty `build_cost` column
  already means for a Machine, and `load_from_directory` lists the file among the ones whose
  absence is an error naming the path — so a Run can never lose the prices quietly and a test
  that never asked for them never meets them.
  `test_structure_costs.test_a_set_that_brings_its_own_recipes_gets_structures_that_are_free`
  is the acceptance criterion as a test.
- **Charged per tile and refunded per tile, through one function.** `_settle_structure_cost`
  takes a tile count and spends it, or hands it back when the count is negative, so a refund
  cannot come to disagree with a charge about the price. Demolishing a Belt returns every plate
  its run cost along with the Items riding it; demolishing a Wall returns its tile's two. An
  Enemy chewing either down returns **nothing**, which is #11's asymmetry applied to the
  cheapest thing a player builds.
- **It lands whole or not at all.** `MISSING_MATERIALS` comes out of `_belt_route_refusal`
  after the ground and before anything is laid, so a route the wallet cannot cover lays not one
  tile and the hash does not move — a route half-laid up to the tile the plate ran out on is a
  player demolishing what they did not ask for, which is the argument that function already
  makes about an obstruction. The wallet is checked **last**, because a player dragging across a
  Machine has a problem they fix by dragging somewhere else.
- **The bill is on screen before the release, and it is the bill for the route.**
  `query_belt_route_cost_items` and `query_belt_route_cost_counts` are projections about a route
  that has not been laid — the arrangement every refusal in this project has — and the HUD's
  route line reads them beside the length. Per route rather than per tile, because the per-tile
  price is a number a player would otherwise multiply by the length while holding a mouse
  button down. The Machine picker's Belt cell quotes the per-tile figure instead, because a cell
  is about the tool and the route line is about the drag.
- **`player.starting_stock` moved with the price and for no other reason.** 110 plate against
  the 78 the opening Factory's Machines cost and the 30 tiles of Belt that join them up: 108,
  and the invariant that line has always stated — the opening line and two plates over — is
  unchanged. Pricing Belts without moving it would have left every measured scenario unable to
  lay the line its Machines were standing waiting for, which is not a balance finding; it is the
  same Factory with the cost of its Belts not budgeted.

What the price actually changed in the measured Runs is **when** a haul gets laid rather than
whether — three scenarios now buy their Belts with the call-early lever, which is a Wave
arriving sooner. See "What the Belt price cost the table", below.


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

### Dying, where a player can see it happen

#54, and the player's own words: *"when the player dies its not fleshed out"*. What dying
looked like before it, measured by rendering one and looking at the picture
([`docs/images/death_before.png`](docs/images/death_before.png)): **you stood bolt upright at
full eye height, the view did not change by one pixel, and the frame was indistinguishable
from being alive.**

**The ticket's own description was one step too generous, and the render is what caught it.**
It said a line appears in the HUD — `DEAD — back at the Nest in 4s`, which at the shipped
eight-second respawn reads 7s — and that line is real, but it is in `_gear_lines`, which only
`hud_text()` carries. The *brief* HUD a player is
actually reading is `_brief_lines`, and it has never mentioned death at all. So a solo death
was presented by **nothing visible whatsoever** except the weapon leaving frame, unless the
player happened to be holding `H`. The before image shows a dead player at the moment the
gesture now has them flat on the deck, and the only way to tell is to read the countdown that
is not there.

**It is presentation and nothing else, and the constraint is the ticket's.** Death costs tempo
and never progress or resources (GLOSSARY.md, DESIGN.md); `_respawn` touches position, health
and the clock, and `test_a_death_leaves_the_stock_the_components_and_the_delivery_counter_alone`
is that sentence as a test. The whole gesture happens *inside* `player.respawn_delay_seconds`
and it could not do otherwise —
`test_the_collapse_cannot_lengthen_the_wait_however_long_it_is_tuned` tunes the fall to a
hundred seconds against an eight-second respawn and asserts the clock does not care, because
`_lives` reads `_respawn_ticks` and has never heard of the collapse.

**Four tuning keys and not one byte of state.** The collapse is a function of
`_player_life_state` and `_player_life_since_tick`, both of which were hashed and saved before
this ticket, so it needed nothing of its own —
`test_the_collapse_is_not_state_and_nothing_in_the_simulation_reads_it` asserts that
mechanically, off `RunSave.state_property_names`, rather than in a sentence.

- **`query_player_collapse_blend` is the shape and the other two are its sizes**, which is the
  arrangement `query_player_sprint_blend` already has beside the field of view and the bob. 0
  standing, rising eased to a resting value as a body goes over, and **the same number run
  backwards when one gets up** — a player who is `LIFE_ALIVE` and has been for less than the
  gesture's length is one rising off the deck. That is the whole of #54's acknowledgement that
  a respawn happened, and it costs no state and no key. A Run **opens on its feet** because
  `_player_life_since_tick` is 0 at construction: nothing had happened to anybody on tick 0.
- **`query_player_view_collapse_metres` and `query_player_view_collapse_roll_turns` are
  renderer-only projections, and that is the ticket's one real decision.** The precedent cuts
  both ways and the rule it is settled by is the **quantity rather than the circumstance**: the
  jump is *in* `query_player_camera_height_metres` because how high a player is standing is a
  fact a round must honour, and the bob, the dip and the lean are out of it because a footfall
  must not move where a round goes. A body going limp is the second kind. The circumstantial
  argument — a dead player aims at nothing, so folding it into the aim would be harmless today
  — is true and is the wrong test: it is true only because `_act_refusal` currently refuses
  every intent of a player who is not on their feet, and the one plausible future in which a
  **Downed** player in co-op is given something to do is one in which a collapse inside the aim
  would quietly be pointing their rounds at the dirt. A projection cannot develop that bug.
- **Both falls are magnitudes rather than eye heights, so 0 means off** — the rule every other
  camera key in `[player]` obeys. They were written as absolute heights first and that was wrong
  twice over: 0 then meant the *largest* possible fall, and there was no single key to switch
  the gesture off with, because `death_view_height_metres = eye_height` was refused by the
  loader's own ordering check. **`death_view_drop_metres = 0` is now the one switch**, drop and
  bank together, because the bank is a fraction of the fall and a fall of nothing is nothing to
  be a fraction of. This is the largest camera movement in the game and somebody prone to motion
  sickness is entitled to turn it off.
- **The loader's ordering check is exempt while the gesture is off**, which is the lesson that
  cost a round of rework: a Downed player cannot have fallen further than a dead one, and that
  is worth refusing by name — but applying it at a death drop of zero is what made the off
  switch two keys. An invariant that fires on the value that means "switched off" is an
  invariant that has forgotten what it is about.
- **A Downed player and a dead one are told apart by posture before they are told apart by
  words.** `downed_view_drop_metres` is 0.9 against the dead 1.42, stated as a fraction of the
  same fall, so the bank comes out proportionally smaller **for free** rather than out of a
  second key somebody has to keep in step. A Downed player who bleeds out goes the rest of the
  way down with no case written for it, because `_lives` restamps `_player_life_since_tick` and
  the blend is a function of the state and the tick it began.

**The overlay is the glance, and the HUD stays the post-mortem.** `WorldView` builds a tint and
two lines of large type once, then shows, hides and recolours them — the rule every other thing
in that file obeys, asserted by alternating a living and a dead Simulation through one view and
counting nodes. There is no state and no tween: everything is a function of the same blend, so
a frame that stepped nothing draws the same thing twice and the overlay puts itself away the
moment a player is upright. Two tints rather than one strength: **Downed is light and warm**
because the only useful thing a bleeding player can do is watch for a teammate coming, and
**dead is darker and neutral** because there is nothing to do but wait.

**The crosshair goes with them, and only a render found it.** It is an aiming reticle, every
intent a dead player could send is refused, and the first render of this gesture had a crisp
white cross sitting in the middle of a body on the deck. It comes back on the tick they are
upright, off the same blend.

**A solo death makes a noise now, which it never did.** `PLAYER_DOWN` fired on
`query_player_is_downed`, which is **never true on a solo Run** (GLOSSARY.md) — so the branch
fired on no solo death ever and #54's own description credits the game with a thud it had never
once made. The cue now fires on leaving your feet, `query_player_is_alive`'s edge, which also
says the right thing about a player who goes Downed and *then* bleeds out: they have fallen
once, so they thud once. No new cue was added and no gain moved — the player has rejected four
separate attempts at sound in this project for being too loud, and an un-auditionable new sting
on the most startling moment in a Run is the wrong risk.

**`tools/visual/compose_death_shot.gd` is the instrument, and the before is honest rather than
reconstructed.** It is a strip, one frame per sample through the fall, through the player's own
camera — the camera cannot be *placed* here, because where the Simulation put it is the whole
subject. Its `before` preset sets `death_view_drop_metres = 0` and gets exactly what shipped,
because the overlay is driven by the very same blend the view is: one key turns off the fall,
the bank and the tint together. Measured off the strip, the fall is 0.08 m at three ticks,
0.90 m at fifteen and 1.42 m with 20 degrees of bank at twenty-seven, where it settles.

```
SHOT_SCRIPT=tools/visual/compose_death_shot.gd tools/visual/shot.sh out.png "dead plain"
```

`dead`, `before` and `downed` are the presets; `bare` hides the yard and **`plain` hides the
first-person arms, which is a licensing requirement rather than a composition choice** — a
render of the purchased RgsDev viewmodels is as non-redistributable as the FBX they came from,
which is why `compose_swing_shot.gd` may never commit its own strip. The committed trio is
[`death_before.png`](docs/images/death_before.png),
[`death_after.png`](docs/images/death_after.png) and
[`death_downed.png`](docs/images/death_downed.png), all at the settled frame.

**Two things recorded rather than patched**, both out of this ticket's scope and both found by
looking at the picture:

- **The brief HUD talks to a corpse.** `Objective.line` is still telling a dead player to press
  B and place a Miner, and `_build_gun_lines` still offers `[B] to draw it`. Neither is wrong
  about the game; both are advice during the one moment a player can act on none of it. The fix
  is a clause in `Objective` and one in `_build_gun_lines`, and it is a HUD ticket.
- **What killed you is still not a question any query can answer.** `_damage_player` takes a
  count of points and nothing about where they came from, and recording it means new hashed,
  saved, replayed state. It is probably worth it — being killed by something you never saw reads
  as unfairness, and this project goes to real lengths elsewhere to make causes legible — but it
  is a change to the Simulation rather than to its presentation, and #54 was explicit that it
  should be argued in its own ticket rather than slipped into this one.

**What no test and no render can settle** is whether half a second is the right length for the
fall, whether 20 degrees of bank is a list or a lurch, and whether the tint is reassuring or
claustrophobic. `player.collapse_seconds`, `player.collapse_roll_degrees` and the two drops are
all hot-reloadable for that reason. The one question that matters most is the one only a human
can answer: **does it read as dying, or as a camera doing something?**

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
- **A Build Gun model arrives the same way an arm does, and since #64 there is one.** The
  seam was always waiting — `build_gun` is an id like any other, so a model under that name
  loads, resolves its clips and draws with **no change to `world_view.gd`** — and what went
  through it is the subject of "The Build Gun is the one thing in a player's hands this
  project made", below. #28 had left the tool as the same two placeholder boxes every
  unconverted weapon gets, sized stubby by a reach of zero, which cost #29's silhouette: a
  flared nozzle and an emissive rail that read as a *tool* rather than a gun at a glance,
  and that distinction is the point of a holster.

### Framing is measured against the frustum, never argued about

The one defect this whole arrangement could not catch. It was reported three times and
fixed wrongly once, and both halves of that are worth keeping, because every future
viewmodel runs the same risk.

A player reported that the knife *"doesnt work"*, twice. Nothing in the code was broken
and nothing was recent: `WeaponAnimator` enters `FIRE` on the tick the trigger goes and
holds it for 32 of the Pneumatic Wrench's 35-tick interval, `WeaponViewmodel` resolves
that role to `Knife_Attack_1_Anim` through the `"attack"` needle, the clip is 0.53 s with
43 tracks that all resolve, and the skeleton moves under the seek. **Every one of those is
assertable headless and every one of them was true the whole time.** What a player could
not do was *see* the swing, because `convert_weapons.sh` framed the arms too close to the
eye for the reach of the take.

- **The middle number of an `--offset` is *forward*, and forward is away from the
  viewer.** It is written in Blender's axes, where +Y is the horizontal depth axis the
  exporter's Y-up conversion sends to glTF -Z — which is the way a Godot camera looks. So
  a **positive** middle number pushes the model out in front of the eye, which is what
  framing a viewmodel by hand means. `test_the_middle_number_of_an_offset_is_forward_and_not_up`
  pins the axis on the committed fixture.
- **"The model's own origin is the eye" is the reason the recipe needs an offset, not the
  reason it does not.** RgsDev ships no authoring camera, so #28 guessed a framing where
  the two `Weapon pack` rifles use `--origin-object Camera001`. The first fix found
  `Prefabs/FPSController.prefab`, which parents those arms to a `WeaponHolder` at
  (0, 0, 0) under the camera, and concluded that the hand number should therefore be only
  a drop — shipping `--offset=0.0,0.0,-0.10`. The prefab fact is true and the conclusion
  does not follow: a rig authored around a camera still has its *hands* 21 cm in front of
  that origin and 20 cm to the right of it, so at the origin the knife hand sits 44
  degrees off the axis at rest and the swing throws it **behind the camera**. That build
  is the one the player described as the knife still not playing, and it was worse than
  what it replaced.
- **The number is bracketed by measuring the take against the frustum.** `player.field_of_view_degrees`
  is 75 vertical, which at 16:9 is 53.8 degrees of horizontal half-angle. The worst thing
  `Knife_Attack_1_Anim` asks for is the `Hand_R` bone a third of a second in, and that
  single reading orders every candidate: 0.00 forward is 89.7 degrees (behind the camera),
  0.16 is 59.2 (the strike is off screen, which is the original defect), 0.30 is 47.7 and
  0.36 is 43.8 but reads small and low. **0.30 forward and 0.24 down** is the nearest
  framing that keeps the whole swing in frame, and it tolerates the field of view being
  tuned down to about 68 degrees before the strike clips again. The recipe carries that
  table beside the number.
- **A state machine with no nodes proves the role, and only a render proves the frame.**
  Every assertion in `test_weapon_viewmodel.gd` was true through all three reports, and
  that is the arrangement working rather than failing: `WeaponAnimator` answers *what
  should be playing* and must have no opinion about whether it is on screen. What was
  missing was any instrument on the other side of that seam, which is why the first fix
  could be reasoned into being worse. **`tools/visual/compose_swing_shot.gd` is that
  instrument**: one frame per tick of a swing, through the player's own camera, which is
  the only form of evidence that a swing is visible.

  ```
  SHOT_SCRIPT=tools/visual/compose_swing_shot.gd bash tools/visual/shot.sh out.png
  ```

  Its strip may **not** be committed, unlike the contact sheets in `docs/images/`: it is a
  picture of the purchased arms and is as non-redistributable as the FBX they came from.

And the reason it surfaced when it did: **#42 made the weapon the default hand**
(`_player_build_mode.fill(0)`), so a player now opens every Run looking at the wrench
instead of switching to it deliberately. The recipe had not changed since 95ee59c created
it. "It doesn't work *now*" was exactly right about the experience and exactly wrong about
the cause.

**What the frustum reading cannot settle is whether the swing reads as a swing.** The arms
are low-poly and pass close to the view, so the strike is most of a forearm crossing the
frame. That it is *in* the frame is measured; that it is *good* is for a human with a
mouse.

**The surface is no longer placeholder-grade, and the sentence that used to stand here was
half wrong.** It said the packs reference textures they do not ship, so everything is
repainted from `dieselpunk_palette.json` rather than textured. The `Weapon pack` ships a
complete PBR set for both rifles; it was never bound. That is #65 — see "The surfaces are
the packs' own where the packs have them", below.

### The surfaces are the packs' own where the packs have them

#65, and the finding is that the sentence this file carried for five tickets was **half
wrong in the half that mattered**. "The packs reference textures they do not ship" — so
every material was repainted a flat palette colour, on the most-looked-at surface in the
game. The `Weapon pack` ships a **complete PBR set for both rifles**: albedo, normal,
roughness, metallic and occlusion, for the L96's body, its scope and its lens, and for the
AKM. Two separate things kept it off the model and either alone would have been enough:

- **The names do not match.** The FBX carries the authoring machine's paths and their
  basenames are not the zip's — `T_S96_ALB.tga.png` against the shipped `L96_ALB.png`,
  `04_-_Default_Mixed_AO.tga.png` against `AO.png`. `--texture-dir` matches by basename, so
  it recovered nothing, and **no normalisation rule bridges S96 to L96**: it is a vendor
  typo.
- **And nothing was ever wired.** These are 3ds Max ShaderFX materials, and Blender's
  importer says so on the way in — `material link b'3dsMax|HwShaderParams|TEX_color_map'
  ignored`, once per map per material. What it builds is a bare Principled BSDF with
  **nothing connected to Base Color** and the images left floating as unreferenced
  datablocks. So finding every file would still have rendered every surface grey.

So `--material-map NAME=CHANNEL:FILE` binds a file to a channel **by path**, in the recipe,
where the rest of the mapping already lives. There is no name to guess at, and **a file
that is not there is fatal, naming the material, the channel and the path** — #57 and #59's
rule, and the thing a flat repaint hid for five tickets. Deliberately harsher than
`--material-colour`, which only reports a material it cannot find: a colour for a missing
material leaves a surface it was never going to improve, where a map names a file somebody
went and found, so a name that binds to nothing means the recipe and the pack have come
apart.

**What genuinely has nothing to recover is the arms, and that was checked rather than
assumed.** All three arm meshes reference `fpArms_Military_D.tga`, `fpArms_AO.tga` and
`fpArms_NRM.tga` from a `FPS Generic Arms/` folder that is **in neither pack** — there is
not one `fpArms_*` file and not one `.tga` anywhere in the quarantine. (The pack does ship
`FPS Arms/Textures/`, but those belong to a separate 346-vertex asset with its own unwrap;
putting its map on the 1422-vertex sleeve would be reading a texture through unrelated
UVs.) The RgsDev rig ships no maps at all, which is a low-poly Unity kit being what it is —
and its UVs say so, the knife's having **8280x** between its tightest and loosest
triangle's metres-per-UV-unit.

Those wear the palette's **own generated maps**, through `--material-surface
NAME=ENTRY[,METRES_PER_TILE]` — literally the surfaces the Machines wear, which is the
sentence the flat repaint was reaching for made literal, and which costs no new art because
`assets/generated/` is committed (#59). The UVs are `machine_parts.box_project_uvs`', #64's
answer for the Build Gun: box-projected at world scale, one UV unit to the metre. It
**replaces** the degenerate unwrap rather than unpicking it, and **adds a UV layer without
moving one vertex**, which is the line this project draws about an artist's mesh.

The entries are not a re-art-direction: each is the palette material the flat colour was
already approximating, and two match on every number — `Blade` was `696A6C` at metallic 1
and roughness 0.45, which is `WeldedSteel` exactly, and `Guard` was `424447` at metallic 1
and 0.62, which is `CastIron` exactly.

#### Four things measurement caught that looking would not have

Every one of these shipped in a render before it was found, and each was found by reading a
number out of the `.glb` rather than by reading the picture.

1. **`image.pixels` hands back the file's own values, not linear ones.** Reading
   `olive_drab_paint.png` with its colour space set to `sRGB` and again set to `Non-Color`
   gives *byte-identical* arrays, both at a mean of 0.4868 — which is 124/255, the file's own
   bytes. Blender applies the transfer function when the **shader samples**, not when Python
   reads. So the first pass multiplied an encoded value by a linear tint and the shader's
   decode squared it: the map embedded at a mean of **57 sRGB where the palette asks for 86**.
   Anything that multiplies a *colour* map linearises first; a `Non-Color` mask must not be
   touched.
2. **`texture_tint` is the wrong number for a thing in the hand, and `base_color` is the
   right one.** The tint brings the generated set back to interwar values for a Machine read
   from metres away through SSAO and fog. Dressed at it, the Pneumatic Wrench's gloves
   measured **129 against a ground of 81** — half again as bright as the world behind them,
   where the flat colour they replaced measured 86. That is #42's Wall, #52's ore and #64's
   brightened tool, **a fourth time**. #64 settled which number reads in the hand, so a map is
   now scaled so its **mean linear value is the palette's `base_color`**: the texture carries
   the variation, `base_color` carries the level, and the gloves came back to 97.
3. **The relief knob is the slope in degrees, not a multiplier.** The generated set is
   albedo-only, so the normal is *derived* — #42's answer on the ground, with the height field
   already in hand. A multiplier means something different on every map: across the palette's
   own four, the same number gives `riveted_steel_plate` **five times** the slope it gives
   `olive_drab_paint`. The first value tried produced **0.66 degrees** on the arms, which is
   exactly the invisible one-degree tilt #42 got from its own physically reasoned guess. The
   knob is now a mean slope, solved for by bisection, so one number suits every surface. And
   it has an **independent calibration**: the pack's own hand-authored `L96_NRM` and
   `Scope_NRM` measure 12.5 and 11.8 degrees, so the shipped 9 sits just under what a real map
   for this asset carries.
4. **Derive the relief before levelling, not after.** Levelling scales the map down towards a
   dark `base_color` and takes its gradients with it — measured, 40% of the slope on
   `olive_drab_paint`. Both numbers were invisible, which is how the ordering went unnoticed
   until the slope was measured in degrees instead of eyeballed.

Two more decisions worth knowing. **The AKM's normal map is DirectX** and says so in its own
file name, so the recipe asks for `normal_dx` and the green channel is inverted — left
alone it lights every slope from the opposite side, which reads as the sun being in the
wrong place rather than as a texture being upside down. And **a palette surface is capped at
512 where a recovered map is capped at 1024**, which is a density measurement rather than a
preference: a palette map *tiles*, so at the 0.12 m a glove is given a 1024 map is 8,500
texels to the metre against the ~1,500 the screen resolves, where a recovered map is one
atlas over a whole 0.9 m rifle and 1024 is already *under* what the screen resolves. That
saving is most of the file — the Pneumatic Wrench went from 11.7 MB to 4.2 MB.

**No picture of any of this may be committed**, and that is the whole of why this section
has no `docs/images/` pair while #64's has one. Every surface #65 changed belongs to a
purchased pack, so a render of it is as non-redistributable as the FBX it came from —
`compose_tool_shot.gd`'s `compare` preset and `compose_swing_shot.gd`'s strip both carry
that rule already. #64 could commit its pair because the Build Gun is this project's own
work. The judgement was made by looking locally, and the measurements above are what can be
written down.

**The Build Gun is deliberately untouched**, and the reason is the licence rather than the
look: `assets/gear/build_gun.glb` is **committed**, so embedding eight 1024-square maps in
it is the 130 MB trade `machine_materials.py` refuses by name. It keeps the palette flat for
#64's reasons. These three are gitignored derivatives of a purchased pack, so embedding
costs a clone nothing.

**What is still wrong, and it is pre-existing rather than new.** The arm sleeve renders as a
bright yellow band — measured at (140, 118, 50) against a ground of (81, 67, 54) — and that
is **specular on a flat low-poly facet**, not albedo: `OliveDrab` is 0.052 linear and no
albedo that dark can produce it. The flat version measured (149, 127, 58) at the same
roughness, so #65 made it slightly *darker* and did not cause it. Fixing it is a decision
about roughness or `KHR_materials_specular` for viewmodels, or about the arms' geometry, and
it wants its own ticket.

**And what no render here can settle** is whether the recovered maps make the rifle read as
*this game's* rifle. They are a clean modern pack's own textures, which is the quarrel
`prop_grade.py` picked with the heyheythere atlas and solved by remapping it onto the
palette's ramps. The rifles were left ungraded deliberately — a weapon is one object held at
arm's length rather than two hundred props filling a yard, and the measured albedo is
already dark — but it is the obvious next question and it is a human's.

### The Build Gun is the one thing in a player's hands this project made

#64, and the fact to carry away is the licence rather than the art: **it is committed.**
Every weapon frame is converted out of a purchased pack, so its `.glb` is a derivative of
something non-redistributable and lives in a gitignored directory most clones do not have.
The Build Gun is assembled by `tools/assets/build_gun_recipe.py` out of `machine_parts` and
`dieselpunk_palette.json` — the same kit and the same numbers every Machine mesh is
generated from — so it is this project's own work, `assets/gear/build_gun.glb` is in git,
and **a clone with no packs at all now holds the real tool.** That is the one thing in this
whole area that does not degrade.

`WeaponViewmodel` gained a second search directory and nothing else. `BODY_DIRECTORIES` is
the committed one then the quarantine, and the order is a decision: the committed side is
the one with a proof behind it (`test_build_gun.py` regenerates the model and compares the
bytes), and the louder failure by far is somebody regenerating the committed tool, rendering
it and seeing no change.

**Being committed moves it to the other half of #57's rule** — *where the output is
committed, prove it; where it is gitignored, date it* — so it is deliberately **absent from
`asset_staleness.py`**, exactly as the Machine meshes and `assets/generated/` are, and the
byte-for-byte regeneration is the stronger instrument in its place.

**The framing is refused rather than argued about, and in three directions.** The rule above
cost three bug reports and one fix that made things worse, and a *generated* viewmodel can do
better than a render because the geometry is in hand: `generate_build_gun.py` projects every
vertex into `player.field_of_view_degrees`' own half-angles and **declines to write a model
that fails**. The single obvious check says the wrong thing, which the first run proved by
refusing a perfectly good model — the stowed pose is *supposed* to be out of frame, so the
rule had to say what it meant:

- **nothing behind the eye, in any pose** — the one defect that has actually shipped here
  (`convert_weapons.sh`'s `--offset=0.0,0.0,-0.10`);
- **the business end inside the frame at rest** — not the whole tool, because a viewmodel's
  grip runs off the bottom edge in every first-person game ever shipped;
- **the business end *outside* it when stowed**, or a `Draw` reads as the tool sliding about
  rather than coming up into frame. That one fired for real: pushing the tool further from
  the eye made the old stow drop subtend a smaller angle, and the generator caught it on the
  next run.

#### Four defects, every one of them found by looking

The pair is [`docs/images/build_gun_before.png`](docs/images/build_gun_before.png) and
[`_after`](docs/images/build_gun_after.png), rebuilt with

```bash
SHOT_SCRIPT=tools/visual/compose_tool_shot.gd tools/visual/shot.sh out.png "tool bare"
```

The before is the ticket's own complaint in one frame: a flat grey rectangle in the
bottom-right corner, behind the hotbar, very nearly the same colour and size as the HUD
panels it is sitting among.

1. **The model loaded, both takes resolved, `has_model` was true, and there was nothing in
   the player's hands.** The tool was frozen at its stowed pose, half a metre below the
   frame, and the cause is symmetrical in a way worth knowing: **both ends of the pipeline
   delete an animation track whose value never changes.** Blender's exporter drops it
   (`export_optimize_animation_keep_anim_object`) and Godot's `generate_scene` drops it
   again (`remove_immutable_tracks`, default **on**). The Build Gun's `Idle` is one key at
   rest on purpose, so it is exactly that track — and `WeaponViewmodel._play` falls a role
   with no clip back to the idle and, failing that, *returns without seeking*, leaving the
   model wherever the last clip left it. With `player.holster_seconds` at 0.06 the opening
   `Draw` is over in three ticks, so what it was left at was `Draw` time zero. **Every
   purchased weapon ships a breathing idle, which is why nothing had ever met this.** The
   related trap is the rest pose: NLA strips hold their first frame over every frame outside
   their range, so the exporter writes a blend of the takes' opening keys as the node's own
   transform unless `extrapolation` is `NOTHING`.
2. **The hotbar is the one thing guaranteed to share the frame with a Build Gun**, because a
   Build Gun is only ever in hand in build mode and build mode is when the Machine picker is
   drawn. The first framing put the tool 25 cm from the eye, down and right — straight into
   the corner the hotbar occupies, with a quarter of the frame of tool behind two rows of
   cells. #48's lesson in a new place, *a mark that is behind something looks exactly like a
   mark that was never drawn*, and **the frustum check could not have caught it, because the
   hotbar is not geometry.**
3. **A silhouette cue that works on a Machine can be the worst possible cue in a hand.** The
   "carries material" cue began as a drum lying athwart the body, which is unmistakable on a
   Machine at thirty metres and hopeless at arm's length: a viewmodel is seen from *behind*,
   so anything across the tool at the near end is the biggest object in frame. Over the
   middle it stood in front of the flared emitter; moved to the breech it filled a third of
   the screen on its own and read as a **drum magazine**, which is precisely what this
   silhouette exists not to be. It is a canister down the left flank now, which is where
   every shipped viewmodel puts its detail and for this reason.
4. **A brightened palette, and it is #42's Wall mistake made a third time.** Defect 1's
   symptom — a tool-shaped nothing — read as "the palette is too dark to use flat", and the
   palette's own comment supplies the argument (*"Where a material has a texture, THE TEXTURE
   CARRIES THE COLOUR"*). Brightened towards each entry's `texture_tint`, the tool measured
   **(212, 187, 146) against a ground of (24, 22, 18)**. The palette was never the problem;
   the model was out of frame for reason 1. **Measure a colour against what will be beside
   it, and fix the bug you have rather than the one the symptom suggests.** The Wall settles
   it by precedent: it is drawn with the palette's own `WeldedSteel` flat and reads correctly.

#### What the comparison settles, and what it does not

`compose_tool_shot.gd`'s **`compare`** preset puts the Build Gun and every weapon frame
through the same camera in turn, and it is the one render that answers the acceptance
criterion — *and the one that may not be committed*, because with the packs linked its weapon
panels are renders of the purchased arms. `compose_swing_shot.gd` has the same rule and
`compose_death_shot.gd`'s `plain` preset is the other half of it.

Read as a set, the answer is not close: every weapon is a long dark rifle running diagonally
across the frame out of a pair of arms, and the Build Gun is short, blocky, pale-ended and
compact, sitting above the hotbar rather than across the view. **Nobody would confuse them at
a glance**, which is the whole of what a holster is for.

**Two things recorded rather than fixed**, both real and both out of scope:

- **The tool has no hands.** Every weapon's model brings the arms with it; a self-authored
  one cannot borrow them, because those arms are the purchased asset. So the Build Gun floats
  where a weapon is held. Modelling a pair of arms is a ticket of its own and it is the
  single biggest remaining difference between the tool and the weapons.
- **At arm's length the parts read as a jumble before they read as a tool.** The three cues
  are individually right and the whole is busy; the honest statement is that the *silhouette*
  is distinct and the *detail* is not yet legible. That is a judgement a human with a mouse
  should make before anybody spends more renders on it.

**What no render can settle** is whether a player who presses `B` now feels they pressed it.
That is the question the whole ticket is about and the one thing none of this measures.

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

**#26 measured the cost of shooting, and #62 measured what a player actually gets.**
`rifle_picket` is the `competent` Factory with a second Belt banking Ammunition at the Nest and
a player standing there with a Bolt Rifle, leaning on the trigger for thirty seconds of every
minute. #26 read it as costing the Run 28 seconds — 26m32s against 27m00s on the schedule of
the day — and the arithmetic beside it said the rifle spends rounds at 75 a minute where the
Ammo Press makes 37.

**That arithmetic is about demand and it was being read as spend. #62 measured the spend and the
row cannot do it:** the Nest's line is a 50/50 branch off one Press, so it pays about nineteen
rounds a minute, and the picket receives 520 over a 27-minute Run, fires all 520, and **holds an
empty gun for 74% of it**. Its thirty-second bursts are mostly dry trigger pulls, which is the
mechanical reason its end-to-end margin has moved five times across five tickets without one of
them touching what a round costs. **Do not read an Ammunition finding into that row**;
`armed_player` is the one to read, because its demand and its income are the same order and it
is dry for 9% rather than 74%.

The honest reading of #26's conclusion survives and gets sharper: **a player who wants to shoot
needs a second production line, and it has to start at the ore.** A second *Ammo Press* off the
one Smelter is the worst build in the table — `armed_second_press` is 14m43s with the player dry
for 83% and 240 rounds stranded in the Factory — because it halves the only Press whose rounds
reach either the lane Turret or the counter. See finding 3 under "What #62 measured".
`test_balance.test_the_rifle_at_the_nest_is_a_fourth_claimant_on_one_ammo_press` and
`test_one_ammo_press_serves_a_turret_and_a_player_only_at_burst_discipline` are what keep both
halves true.

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
  `content/` unaltered: 110 plate, an opening line that costs 78 in Machines and nine tiles of
  Belt on that compact Map, a second Ammo Press at 14, and the change spent on Wall so the
  premise is empty pockets.
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
the one Stratagem the shipped chain does not lock. Measured with #60 in, the Run is **16m40s**
against `competent`'s 28m48s — 42% shorter — with 7 Charges banked at the peak against a capacity
of 8 and 20 rounds still in the Factory at the end. (The figure stood at 15m22s between #46 and
#47; #47's Belt price bought the row's Belts with lever pulls and moved it out again, and #60
re-derived 16m40s. See "What the Belt price and the declared port cost the table".)
**Nothing in `content/` changed to make any of that true.**

**And #60 measured the alternative this paragraph rules out.** "The Silo's plate is better *made*
than branched off it" is still the right call and the reason given above is not the reason:
`branched_artillery` does branch the one Smelter, the Press is *not* starved out, and the Silo
fires — but the haul that carries plate round to where the Silo stands is thirty-five tiles, so
branching costs 35 plate against the second ore line's 24 and parks 104 plate on a conveyor. See
finding 3 under "What #60 measured".

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
- `tests/balance_scenarios.gd` — the **seventeen** sessions of record, on `MapLayout.starter()`
  with `content/` off disk and `player.starting_stock` as written. Every one past `bare` contains
  the same six Machines on the same tiles, so the difference between two rows is the difference
  between two *decisions*. Nine are #26's and #37's; the six #60 added are each a claim this file
  had been making on arithmetic; the two #62 added are the player's own magazine, which nothing
  here had ever measured. **A variant is built by one private shared with the row it varies**,
  under a flag, so the row of record cannot drift from its own variant — `coal_haul` and
  `deep_silo` of `deep_digger`, `branched_artillery` of `artillery`, and `armed_second_press` of
  `armed_player`.

`tests/cases/test_balance.gd` asserts the shape in bands rather than ticks — the exact figures
belong here, and a test that pinned the tick would turn every legitimate tuning change into a
red suite. It costs the suite about two minutes, which is why it caches a played Run and reads
it from several methods.

### The table, measured 2026-10-09

Seeds 7, 11 and 29. **Fifteen of the seventeen scenarios end on the same tick on all three**,
and the two that spread are the two that fire enough rounds to. `rifle_picket` spreads again —
27m18s, 27m20s and 26m39s, the identical figures #47, #49, #58 and #60 measured — and #62's
`armed_player` joins it at 24m14s, 24m15s and 24m15s. `Simulation._scatter` is the only consumer
of the seeded RNG in `sim/` and only a *ranged* shot reaches it, so this is the property behaving
rather than changing: the six rows #60 added fire nothing and are identical, and #62's
`armed_second_press` fires 133 shots and is identical too. See "What the seed can reach", below.

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
to the mechanic alone — see "What #46 cost the table". The seventh is #47's Belt price and
declared ports, measured together, and **six of the nine rows did not move at all** — see "What
the Belt price and the declared port cost the table". It is one fresh run of
`tools/balance/measure.sh` on the tree with #38 merged in, re-run after that merge rather than
carried across it, because the rule this file keeps is that a measured figure is rewritten from a
measurement and never reconciled with one. The eighth is **#49's bigger Breaker**, and **not one
of the nine rows moved by a single tick** — see "What a bigger Breaker cost the table", below,
for why that is the expected answer rather than a suspicious one. **#58 gets no column**, for
the same reason and more strongly: it made an Enemy's reach care how high a player is standing,
and no scenario here ever leaves the ground, so all nine rows reproduced #49's exactly and the
clause it added was unreachable. That is a gap in the instrument rather than a measurement of
the mechanic — see "What roof cover cost the table". The ninth and last is **#60**, which moved
no row of record either — all nine reproduced #49's figures exactly, which is the **second** time
this table has been independently re-derived by a later ticket rather than carried forward — and
added **six rows**, every one of them a claim this file had been making on arithmetic. See "What
#60 measured, and the four claims it contradicted", below.

**#62 gets no column either, and for the strongest reason in the list.** It added figures to the
*report* rather than rules to the Simulation — the player's own magazine, which nothing here had
ever measured — so there was nothing it could have moved, and all fifteen rows of record
reproduced #60's figures exactly on all three seeds. What it added is the two rows at the bottom
of the table, and one correction: `competent`'s Ammunition stockpile peaks at **446** around
minute twenty-three rather than the 454 at minute twenty-four this file had been carrying. See
"What #62 measured", below.

The six rows below the rule are #60's and have no history: they were measured once, on the tip
they were written against. The last two are **#62's**, and the same applies — except that #62
re-measured all fifteen rows of record and **every one of them reproduced #60's figures
exactly**, down to the Wave number, the peak Heat and the list of Machines lost in the order
they were lost. That is the **fourth** independent re-derivation of this table.

| Scenario | #26 before | #26 after | #34 | #37 | merged | #46 | #47 | #49 | **#60** | Wave | Peak Heat | What killed it, now |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `bare` — builds nothing | 4m22s | 4m22s | 4m22s | 4m22s | 3m22s | 3m22s | 3m22s | 3m22s | **3m22s** | 1 | 0 | undefended: the first Wave alone |
| `opening_line` — the line, no Turret | 3m39s | 4m04s | 4m04s | 4m04s | 3m12s | 3m12s | 3m12s | 3m12s | **3m12s** | 1 | 615 | undefended, and *sooner than `bare`* |
| `competent` — six Machines, one MG on the lane | 17m45s | 27m00s | 29m07s | 29m07s | 28m48s | 28m48s | 28m48s | 28m48s | **28m48s** | 35 | 6725 | **a Siege Hulk standing**, 96 rounds still in it |
| `over_producer` — the same plus an unbelted Miner | 10m30s | 19m36s | 20m21s | 20m21s | 20m21s | 20m21s | 20m21s | 20m21s | **20m21s** | 25 | 6841 | the same, **29% sooner** than `competent` |
| `fortified` — a second MG over the Factory | 8m08s | 29m15s | 28m45s | 28m45s | 28m45s | 28m45s | 28m45s | 28m45s | **28m45s** | 35 | 6716 | the same, 112 rounds unspent — **a wash** |
| `deep_digger` — pays the chain, digs Depth 2 | 8m13s | 10m48s | 10m48s | 10m48s | 10m48s | 11m03s | 12m27s | 12m27s | **12m27s** | 15 | 3538 | swarmed, 16 rounds left, with **two Breaches** open |
| `hive_sortie` — clears the eastern Hive | 19m13s | 29m36s | 32m22s | 32m22s | 32m05s | 32m05s | 32m05s | 32m05s | **32m05s** | 39 | 6672 | the same, 3m17s *later* — the longest Run measured |
| `rifle_picket` — a rifleman on the same Press | 8m04s | 26m32s | 27m16s | 27m16s | 28m02s | 28m02s | 27m18s | 27m18s | **27m18s** | 33 | 6051 | swarmed, 1m30s sooner than `competent` |
| `artillery` — grows a Silo and fires it | — | — | — | 16m10s | 16m10s | 15m22s | 16m40s | 16m40s | **16m40s** | 22 | 5433 | swarmed, **42% sooner** than `competent` |
| `second_press` — a second Ammo Press **and** a second Turret | — | — | — | — | — | — | — | — | **24m14s** | 29 | 5464 | swarmed with **416 rounds still in it** — 16% *sooner* than `competent` |
| `walled_lane` — a funnel of Wall instead of the second MG | — | — | — | — | — | — | — | — | **28m45s** | 35 | 6716 | the same as `competent`; 11 Walls, all standing, **0 hit points absorbed** |
| `sealed_breach` — four Walls shutting the one Breach | — | — | — | — | — | — | — | — | **26m42s** | 32 | 5448 | **ran dry**; 7 Walls built, 3 left, **980 hit points absorbed** |
| `branched_artillery` — the Silo off one Smelter, no second ore line | — | — | — | — | — | — | — | — | **13m57s** | 15 | 2974 | swarmed; the Silo fired, and 104 plate was parked on the haul |
| `deep_silo` — `deep_digger` with a Silo, going for a Barrage | — | — | — | — | — | — | — | — | **12m59s** | 16 | 3477 | swarmed with two Breaches open; **the Barrage was never unlocked** |
| `coal_haul` — `deep_digger` that never tears the haul down | — | — | — | — | — | — | — | — | **15m41s** | 17 | 2488 | swarmed, browned out for **47%** — and **3m14s *longer*** than `deep_digger` |
| `armed_player` — a player arming himself at the counter, firing in bursts | — | — | — | — | — | — | — | — | **24m14s** | 28 | 5447 | swarmed; the player was **dry for 9%** of 1434 s, firing 374 shots out of 452 rounds |
| `armed_second_press` — the same player, on #60's second Press and Turret | — | — | — | — | — | — | — | — | **14m43s** | 15 | 3199 | swarmed with **240 rounds** in it and **nothing lost**; the player **dry for 83%** |

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

### What the Belt price and the declared port cost the table

**Two changes measured together, and six of the nine rows did not move by a tick.** That is the
control the shape of this ticket predicted and the most useful thing in the measurement, so it is
worth saying why before the three rows that did.

- **The declared port moved nothing, because every scenario Belt already docked legally.** This
  was checked rather than hoped for: the shipped ports table was *re-declared against the Factory
  the scenarios actually build* — a Miner's ore leaves by whichever face the line runs along, an
  Ammo Press gives rounds back on three faces because `competent` takes two lines off its western
  wall and one off its eastern, a Smelter takes ore on the north and coal on the west because that
  is where its Belts arrive. Declaring the table to match the game that exists is content design
  and the better half of this change; the alternative was re-routing every Factory in the project
  to suit a declaration nobody had ever validated. One fixture did have to move — see below.
- **The Belt price moved nothing where the opening bill absorbed it**, which is six rows.
  `player.starting_stock` went 80 to 110 so the documented Factory's thirty tiles are budgeted,
  and `bare`, `opening_line`, `competent`, `over_producer`, `fortified` and `hive_sortie` are
  bit-identical across all three seeds to the figures #46 measured.

The three that moved all moved for the same reason, and it is the reason the price exists: **a
haul that used to be free is now bought with a pull of the call-early lever**, which is a Wave
arriving sooner.

- **`deep_digger` is 12m27s against 11m03s — a minute and a half *longer*.** Its two Nest lines
  are forty and twenty-four tiles, 64 plate against an opening bill budgeted for the Factory's
  own thirty, so they wait on the lever: two pulls buy the coal line at two minutes and a third
  buys the ammunition line at three, where both used to go up at tick 3. The coal line therefore
  diverts the Boiler's fuel later and comes down at five minutes rather than three. More of the
  Run is spent with a Boiler that is actually burning, so the Factory produces more, carries 18%
  more peak Heat and reaches Wave 15 rather than 12 — and still digs to Depth 2 and still opens
  its second Breach, which is what the row measures. **The lesson the price teaches is the one
  finding 9 said nothing said out loud:** a forty-tile haul to pay a twenty-coal bill is now a
  visible forty-plate decision made before the drag is released.
- **`artillery` is 16m40s against 15m22s, 78 seconds longer**, by the same mechanism in a row that
  was already lever-funded: its four extra Belts cost plate the lever has to find first, so the
  Silo stands up later, and a Run that spends less of itself at 1,060 kW of demand lasts longer.
  It still powers, loads and fires. 42% of `competent` rather than 47%.
- **`rifle_picket` is 27m18s against 28m02s, 44 seconds shorter, and its sign has now moved for
  the fifth time.** The twenty-four-tile line that banks his magazine costs 24 plate, bought with
  one lever pull the row did not carry before. `SAME_LENGTH_SECONDS` widened from 90 to 150 to
  keep the claim it guards — a rifleman is neither free nor ruinous — because 90 seconds exactly
  is the measured margin and would sit on the old boundary. **Do not read an Ammunition finding
  into it**: five tickets have now moved this margin without one of them touching what a round
  costs or what a Press makes.

**No balance number was changed to make any of this true**, and the one tuning value that moved —
`player.starting_stock`, 80 to 110 — moved with the Belt price and is budgeted from it rather than
chosen: 78 of Machines plus the 30 tiles the documented Factory needs, and two over, which is the
invariant that line has always stated.

**One fixture's docking changed and its meaning changed with it**, which is worth recording
plainly because it is the one place the declaration contradicted a Factory somebody had written.
`test_nest_store`'s opening line runs **east to west** — ore from a Miner at x = 12 into a Smelter
at x = 7, plate on westward to the Nest — and a Smelter stood square takes ore on its north and
west faces and gives plate back on its south and east. Stood square in that line it faces the
wrong way and neither of its Belts connects. The fixture now builds the Smelter and the Boiler
**turned half round**, which is what the arrows on them say and what a player would do. What
changed in meaning is that the fixture is now also a statement about rotation: it says a Factory
can be built in either direction *provided the Machines are turned to suit*, which before this
ticket was not a thing a Factory could get wrong. `test_belts`'s branching Smelter moved for the
same reason — its second branch left by the Smelter's northern wall, which is an input face, and
now leaves by the southern one.


### What a bigger Breaker cost the table

**#49 raised a Breaker's hit volume and every one of the nine rows is bit-identical to #47's,
on all three seeds, down to the Wave number, the peak Heat and the list of Machines lost.** The
change was made for readability — a Crawler and a Breaker were the same dark silhouette at
thirty metres — but `enemy.breaker_hit_radius_metres` and `breaker_hit_height_metres` are the
capsule a round is resolved against, so it is a combat quantity and was measured rather than
reasoned about.

**The null result is explained by who reads that capsule, and it is a shorter list than it
looks.** Grep `_enemy_hit_radius` and `_enemy_hit_height` and there are exactly two consumers:

- **`_shot_target`** — a *player's* ranged weapon, which resolves against the capsule with three
  tests in the order that rejects most cheaply.
- **`_enemy_bite_reach`** — `enemy.player_bite_reach_metres` plus the radius, so how close an
  Enemy has to be to bite a *player*.

**A Turret reads neither.** `_fire` takes its target from `_turret_target_index`, which acquires
on the distance to the Enemy's *point* against `range_tiles` and never against a hit volume at
all — so the thing that does nearly all of the killing in every row of this table is untouched
by construction. That is the whole of why nothing moved, and it is worth knowing in its own
right: **a Breaker's size is a fact about what a player can shoot and what can bite a player,
and not a fact about the Factory's own defence.**

Of the nine scenarios only `rifle_picket` fires a player's weapon, and it is the row least able
to show the difference: it reaches the Breaker tier's 5200 Heat only in its last minutes, and it
ends with 18 rounds left because it has been rationing throughout. So the one row that *could*
have moved had almost no Breaker to shoot at while it still had rounds.

**The one balance consequence that is real and unmeasured** is the other consumer: a Breaker
bites a player from 0.2 m further out than it did, because reach is measured from the hull and
the hull got wider. Nothing in the nine scenarios stands next to a Breaker on purpose — the
same hole that leaves hand repair under fire unmeasured — so that is an arithmetic claim, and it
is listed under "What is still unmeasured" with the others rather than dressed up as a finding.

### What roof cover cost the table

**#58 made an Enemy's reach care how high a player is standing, and every one of the nine rows
is bit-identical to #49's on all three seeds** — the Run length, the Wave, the peak Heat and the
list of Machines lost. Measured rather than reasoned about, because the rule is a combat
quantity and this project has twice paid for a tuning change nobody played.

**The null result is explained by the harness rather than by the mechanic, and that is the
honest reading.** `_player_in_contact` is the one function that changed and the new clause fires
only when `_player_y` is above the biting kind's own height. **No scenario in
`tests/balance_scenarios.gd` ever leaves the ground**: nothing jumps, nothing is built on top of
anybody, and the two rows whose player walks anywhere — `hive_sortie` and `rifle_picket` — walk
on clear ground, the first because #30's collision forced it round the Factory rather than
through it. So `_player_y` is zero for every tick of all twenty-seven Runs and the clause is
unreachable by construction.

That is worth stating as a **gap in the instrument** rather than as evidence the change is free.
The thing a table of nine ground-bound scenarios can confirm is that the ground case did not
move, which is the regression that mattered and which
`test_roof_cover.test_an_enemy_still_bites_a_player_standing_on_the_ground` also pins on both
kinds. What it cannot say is what a roof is worth to a player who uses one, and that is the same
category as hand repair under fire: it needs somebody who can climb a Boiler when a Wave arrives
and decide whether doing so felt clever or cheap. The scenario that would begin to say is a
`competent` Factory whose player stands on its Ammo Press through the Breaker tier — and the
interesting half of it, whether the Breaker eating the floor reads as the right answer, is a
question about watching rather than about a Run length.

### What #60 measured, and the four claims it contradicted

**#60 added six rows and moved none of the nine, and every one of the six is a claim this file
had been making on arithmetic.** The list it worked from is "What is still unmeasured", below,
which had been accumulating across five tickets. Nothing in `content/` changed; the rows report
what the Runs did, and four of them report something other than what was expected. Those four
are the deliverable.

**The nine rows of record reproduced #49's figures exactly** — every clock, every Wave number,
every peak Heat, every list of Machines lost in the order they were lost, on all three seeds.
That is the second time this table has been independently re-derived rather than carried
forward, which is the only thing that makes the history columns worth keeping.

#### 1. A second Ammo Press and a second Turret make the Run *shorter*, and the reason is not Ammunition

The Turrets section has said since #10 that a second Ammo Press is "the arithmetic answer to the
middle of the Run", and #34 sharpened it rather than answering it: `competent` ends with 96
rounds unspent and `fortified` with 112, so **one Turret cannot spend what one Press makes**.
The obvious next build is both at once — more Ammunition *and* somewhere to put it — and nobody
had played it.

`second_press` is that build: a second Ammo Press at (14, 10) fed by a second Belt off the one
Smelter's eastern wall, and a second MG at (11, 7) fed by the Press, bought with two pulls of the
call-early lever. Measured, it is **24m14s against `competent`'s 28m48s — 16% shorter — and it
ends holding 416 rounds**, more than four times what `competent` ends holding.

Three figures explain it and the third is the finding:

- **It defended the Factory well.** Two Machines lost against `competent`'s six, and six still
  standing at the end. Both Turrets were fed the whole Run: the Factory held no Ammunition at all
  for 0% of the endgame.
- **It never reached the boss.** Peak Heat 5464 against `siege_hulks.min_heat` of 6400, so this is
  the only long Run in the table that is **not** ended by a Siege Hulk. It was swarmed at Wave 29.
- **The two Turrets fired 464 shots in 24 minutes**, which is nineteen a minute against a rate of
  240 a minute while they have a target. So **a Turret's output is bounded by how long an Enemy
  spends inside its 16 m, and not by its magazine at all.** A second gun covering the same
  Factory adds coverage, not throughput; a second Press adds rounds to a stockpile that was
  already growing.

What it *did* add was Heat and Power: the Press's crafts are crafts, and `heat.per_craft` charges
them whether or not anything shoots the rounds. The Factory ran at 180 Heat a minute against
180 a minute of decay — exactly break-even on the shipped two-Hive Map — and the Waves arrived
four and a half minutes sooner for it.

**So the arithmetic answer is wrong, and `over_producer`'s lesson is wider than `over_producer`.**
That row makes over-production obvious by belting a Miner to nothing; `second_press` makes the
same mistake with a build that looks completely sensible, and the only thing on screen that says
so is a stockpile climbing to 432. **Nothing is re-tuned for this** — it is a finding about what
the numbers mean, not an argument that one of them is wrong — but it does say where to look if
the mid-game ever wants to reward production in combat power: a Turret that cannot spend what one
Press makes is a Turret whose *reach* or whose rate of fire is the lever, not its feed.

#### 2. A Wall that can be walked round is never bitten, and sealing the Breach is the only thing that gets one chewed

`wall.health` is 240 against a Breaker's 60 a second, and since #47 a Wall costs two plate a tile
— priced against a Belt's one on an argument about what a player would rather lose, with nothing
measuring whether anybody ever wants one at that price. Two rows now do.

- **`walled_lane`** spends `fortified`'s single pull of the lever on eleven tiles of Wall across
  the lane at x = 6 instead of on a second MG, with the Breach's own latitude left open so the
  Wave funnels through a gap three and a half tiles from the Turret — every tile of the line
  inside its 16 m reach, which is the best case a Wall has on a Map with no choke in it.
  Measured: **28m45s, eleven Walls built, eleven still standing, and zero hit points absorbed
  between them.** It lands within three seconds of `competent` and on exactly `fortified`'s clock,
  which is the lever pull and nothing else.
- **`sealed_breach`** boxes the one Breach in with four tiles — eight plate — so that Enemies
  emerge into a pocket they cannot route out of. Measured: **7 Walls built, 3 left standing, and
  980 hit points absorbed**, which is four Walls chewed all the way through and three replaced
  while the lever's change lasted. The Run is 26m42s, two minutes short of `competent`, and it is
  the one row in the whole table whose cause is **"ran dry"** — 49% of the last two minutes with
  no Ammunition anywhere in the Factory.

**The mechanism behind both is one clause.** `_enemy_contact_target` chews a Wall in exactly one
case: an Enemy in a pocket it cannot route out of, Machines before Walls. A Breaker prefers
Machines and a Wall is not one; a Crawler with a route walks past. So **a Wall in the open is a
detour and never a defence**, however much of it a player pays for, and `wall.health` against
`enemy.breaker_damage` is only reachable by sealing something.

Two consequences worth keeping:

- **Two plates a tile is not obviously the wrong price, because the price is not what makes a
  funnel worthless.** Free Walls across that lane would have absorbed the same zero hit points.
  The question a human has to answer is whether re-routing a Wave through a kill zone *feels*
  like a defence; the harness says it does not lengthen a Run.
- **A seal is a real mechanic with a real number on it now.** 980 hit points of chewing held the
  Breach shut and cost the Run two minutes, because the Wave was held fourteen tiles from the
  Turret — out of its reach — chewing in peace and arriving all at once. `test_machine_mortality`
  already asserts a seal buys time rather than stopping a Wave; what is new is that on the
  shipped Map it buys time **the Turret cannot use**.

#### 3. Branching one Smelter is dearer than building a second one, and the arithmetic left out the geography

CLAUDE.md has said since #46 that the sharpest unmeasured row is `artillery` **without** its
second ore line, feeding the Silo's plate off a branch of the first Smelter: "it would save 20
plate and two Machines' worth of Heat and Power… the arithmetic says it works". `branched_artillery`
is that row, and the arithmetic was right about the mechanism and wrong about the cost.

**It works.** A Silo stood up on a branch of the one Smelter, banked two Charges, and fired a
Sentry Drop with nothing wasted — and the Press was not starved out: the Factory held no
Ammunition at all for 0% of the endgame. One Machine lost. That is #46's mechanic carrying a whole
Run rather than a fixture.

**It does not pay**, for a reason no amount of tuning the Recipe would have shown. The Silo stands
where the second ore line put it, in the clear ground south of the Nest, so plate from the first
Smelter has to travel the long way round the Factory and the Nest to reach its western wall:
**thirty-five tiles, which is 35 plate against the 24 the Miner, the Smelter and their four Belts
cost.** So the "saving" is negative in the only currency a Run has. And thirty-five tiles is
thirty-five items of buffer: the row ends with **104 iron plate parked on that haul**, which is
five and a half minutes of the Smelter's entire output sitting on a conveyor. The Run is
**13m57s against `artillery`'s 16m40s**.

That is finding 9's shape — a long Belt is a long buffer — in a line nobody would have called a
haul, and it is the general lesson: **on this Map a branch is only cheaper than a second line if
the consumer is already next to the producer.**

#### 4. No Run in Milestone 1 can unlock the Artillery Barrage, and the reason is the Delivery chain's own bill

The standing claim was that "the next scenario worth writing is `deep_digger` with a Silo, which
is the only Run that reaches a Barrage at all". It is the only Run that reaches Depth 2, and it
does not reach a Barrage.

`artillery_barrage` sits behind **`t03_deep_survey`, which wants 400 iron plate and 200 coal at
Depth 2**. One Smelter makes 18.75 plate a minute, so 400 plate is twenty-one minutes of its
entire output with nothing going to the Ammo Press — and `deep_silo` lasts **12m59s**. The row is
two orders of decision away from the tier, not one.

What `deep_silo` *does* measure is worth having, and all of it is new:

- **A Run can pay the chain and stand a Silo up.** Depth 2 reached, `t01_munitions` and
  `t02_deep_mining` both finished, `supply_drop` unlocked, a Silo standing at the end with nine
  Machines and **none lost**, 17% of the Run in Power deficit with a second Boiler carrying the
  Silo's 400 kW.
- **And it cannot fill it in time.** The Silo went up at about minute eleven and banked its first
  Charge with **five seconds of Run left**. The plate for a Silo and the plate for the chain are
  the same call-early plate, and the Ammo Press is feeding the Turret and the Silo while the
  Smelter is feeding the Press and the Silo — so a twenty-round Charge takes over two minutes to
  assemble. Measured the other way round, a variant that abandoned the chain at minute six fired
  a Sentry Drop and reached Depth 1: **a Run gets the chain or it gets artillery, not both.**
- **So `silo.paint_seconds` at five seconds and a Barrage's 150 points over six tiles are still
  unmeasured, and the reason has moved.** It is no longer "nobody wrote the scenario"; it is that
  no Factory in Milestone 1 can buy the row. A Supply Drop is unlocked and unfired for the
  narrower reason above, and the scenario that would fire one is a **`competent` Factory that pays
  `t02_deep_mining` and then builds a Silo** — twenty-eight minutes of Run rather than thirteen.
  That is the next row worth writing and it is named in "What is still unmeasured".

#### 5. Finding 9's trap has inverted: a long coal haul left standing now makes the Run *longer*

Finding 9 records that `deep_digger`'s forty-tile coal haul holds 160 coal before back-pressure
reaches the Miner, so a line nobody tears down goes on diverting the Boiler's fuel — measured
**before #46**, when that line took *all* the Miner's coal rather than half, at **6m20s with 98%
of the Run browned out, against 10m48s with the demolish in.** #46 changed exactly the quantity
that figure depended on and nobody re-measured it. `coal_haul` is `deep_digger` with one segment
removed and nothing else.

**On a fair share it is 15m41s against `deep_digger`'s 12m27s — three minutes and fourteen seconds
longer.** The Power figure did not get better, it got worse: **47% of the Run in deficit** against
`deep_digger`'s 17%. What changed is what that deficit buys:

- **Half the coal is enough to keep the Boiler relighting**, so the Factory sags rather than
  stopping. All seven Machines were still standing at the end and the Turret still fired 262
  shots against the torn-down Run's 269.
- **A browned-out Factory is a cool Factory.** Peak Heat **2488 against 3538** — 30% lower — and
  the Wave interval sat at its 40-second floor for only 10% of the Run against 24%. Every lump of
  coal parked on that Belt is a lump not being burned into a craft, and a craft is what Heat is
  made of.

So the trap is a **buffer** now and not a tax, and the mechanism is the one Heat was designed
around: throttling your own Factory throttles the thing hunting you. That is an uncomfortable
finding rather than a comfortable one — it says a player can buy Run length by deliberately
under-powering themselves — and **nothing is re-tuned for it here**, because it is a consequence
of `heat.decay_per_minute` against what a working Factory makes, and moving either is a decision
with a human in it. The honest statement is the one the figures support: on the shipped numbers a
Factory that cannot run flat out lives longer than one that can.

### What #62 measured, and the row whose premise was never true

**#62 added two rows and moved none of the fifteen, and the question it was opened for had been
open since #15.** `player.starting_stock` is plate alone, deliberately — rounds in the opening
bill would conjure the one thing the Factory exists to make — so a Run opens with a rifle that is
a stick, and #27's faucet at the Nest is the only way it ever fires. `test_gear` walks that chain
once. Whether it *keeps up* across a Run, against the Turret drinking from the same Ammo Press,
had never been played, and this file recorded it as open.

**The instrument had to be built before the question could be asked, and that is the first
finding.** `BalanceProbe`'s dryness verdict is about the **Factory**: `query_item_total` walks
Machines and Belts and has never heard of the Nest's store or of a player's pockets. So every
figure this table has ever printed about Ammunition was silent on whether the person holding the
gun had anything to fire — a Run can report a perfectly fed Factory while the player standing at
its counter is empty, and `armed_second_press` below is exactly that Run. The Report now carries
`player_armed_ticks`, `player_dry_ticks`, `player_shots_fired`, `rounds_that_reached_the_player`
and `most_in_the_nests_store`, counted **only over the ticks a ranged weapon was in hand** —
`query_player_weapon_ammunition_per_shot` is 0 for a Pneumatic Wrench, so a player holding one is
not dry, they are not in the market, and a figure that counted those ticks would report
**fourteen of the seventeen rows** as dry for the whole of themselves — only `rifle_picket` and
#62's own two ever draw a ranged weapon.

#### 1. One Ammo Press serves a Turret and a player, and the lever is discipline rather than supply

`armed_player` is the `competent` Factory plus the twenty-four-tile haul that banks rounds at the
counter — bought with one pull of the call-early lever, which is exactly what `rifle_picket`
pays — and a player who withdraws whatever the store has every forty seconds and spends an
eight-second burst. Eight seconds is ten shots at `bolt_rifle`'s 0.8 s, which is a Wave's worth
of Chaff and not a round more; forty seconds is `heat.wave_interval_minimum_seconds`, the floor a
long Run spends most of itself pinned at.

Measured: **24m14s, Wave 28, peak Heat 5447. The player held the gun for 1434 s and was dry for
9% of it, firing 374 shots out of the 452 rounds that reached him.** So the answer is yes — and
the two armed rows together say *why*, which is the part worth keeping:

| | armed for | rounds reached him | that is | he fired | dry |
|---|---|---|---|---|---|
| `armed_player` — bursts | 1434 s | 452 | 18.9 a minute | 374 | **9%** |
| `rifle_picket` — leaning on it | 1618 s | 520 | 19.3 a minute | 520 | **74%** |

**The income is the same and the dryness is not, so the faucet sets what a player earns and
their trigger discipline sets whether they are armed when it matters.** The Nest's line is a
50/50 branch off the one Press (#46), so it pays about **nineteen rounds a minute whatever the
player does** — half of the Press's 37.5, which is itself the Smelter's 18.75 plate doubled. A
Bolt Rifle leaning on the trigger demands 75 a minute against that nineteen and stands empty
three-quarters of the Run; one firing at Waves demands about fifteen and is ready for almost all
of them.

**What it costs the Turret is real and is the first measured figure for it.** The player's share
comes out of the same branch, so the gun holding the lane spent **4431 Turret-ticks empty against
`competent`'s 2162** and fired **418 shots against 715** — and the Run is **24m14s against
28m48s, 4m34s and 16% shorter**. The Nest's store peaked at **24 of its 200 cap**, which is the
sharpest single number here: there was never a reserve, only a pipe. A player arming themselves
out of their own Factory is living hand to mouth by construction, and the cap is not what bounds
them.

(That 24m14s is the same clock `second_press` prints, and it is a coincidence rather than a
mechanism — different Wave, different peak Heat, and nothing shared but the shape of the loss.)

#### 2. `rifle_picket`'s own premise was never true, which is why its margin was never readable

This is the finding that outlives the two rows. `rifle_picket`'s note in this file says it draws
"a magazine a minute and spending half of each minute on the trigger", and that **the rifle
spends rounds at 75 a minute where the Ammo Press makes 37**. The second half is arithmetic about
*demand* and it was being read as a statement about *spend*. Measured, the row cannot spend 75 a
minute and never did: it receives 19, fires 19, and **holds an empty gun for 74% of the Run**, so
its thirty-second bursts are mostly dry trigger pulls.

So the mechanical reason this file has recorded — that the picket's end-to-end margin moved five
times across five tickets without one of them touching what a round costs or what a Press makes —
is now a measurement rather than a shrug. **The demand the row was built to measure never
happened.** What the row actually measures is a player who fires until empty and then waits, and
the difference between it and `competent` is dominated by where its ~19 rounds a minute happened
to land. The standing instruction not to re-tune Ammunition off that margin is unchanged and now
has a reason attached; `armed_player` is the row to read instead, because its demand and its
income are the same order.

#### 3. A second Ammo Press off the one Smelter is the worst build in the table

**#60's finding 1, sharpened past "a mistake" into "a net subtraction".** #60 measured
`second_press` as 16% shorter than `competent` with 416 rounds nobody could spend, because a
Turret's output is bounded by how long an Enemy spends inside its 16 m and not by its feed. What
that left open was the player's side: a player is not range-bound, so rounds a Turret cannot
spend ought to be rounds a player could.

`armed_second_press` builds exactly what `second_press` builds, on the same tiles, out of the
same two extra pulls of the lever, and puts `armed_player`'s rifleman at the counter. Measured:
**14m43s — 39% shorter than `armed_player`, 49% shorter than `competent`, and the shortest
defended Run in this table — with the player dry for 83% of the time, 137 rounds reaching him
against 452, and the Factory finishing on 240 rounds with all eight Machines standing and nothing
lost at all.** A Factory in perfect health that cannot shoot.

**The reason is #46's 50/50 share applied twice over, and it is worth doing the arithmetic
because no single row shows it.** Trace what the gun holding the lane is actually fed, in rounds
a minute, remembering that one Smelter makes 18.75 plate a minute and a Press turns each plate
into two rounds:

| | plate into Press 1 | rounds out | Press 1's branches | **to the lane Turret** |
|---|---|---|---|---|
| `competent` | all 18.75 | 37.5 | the Turret alone | **37.5** |
| `second_press` | half, 9.4 | 18.75 | the Turret alone | **18.75** |
| `armed_player` | all 18.75 | 37.5 | the Turret and the Nest | **18.75** |
| `armed_second_press` | half, 9.4 | 18.75 | the Turret and the Nest | **9.4** |

So the second Press and the player each halve the lane Turret's feed, and **`armed_second_press`
is the only build in the table where both halvings land on the same Press** — a quarter of what
`competent` feeds the gun that is holding the road. The second Press's own rounds go to the
second Turret and never come near the store, so they cannot make up either shortfall: two Turrets
managed **169 shots** between them and the Breaker tier was never even reached. That is the
subtraction, and it is why nothing about #60's row predicted it: `second_press` halves the feed
once and survives it.

**What a player who wants to shoot needs is a second Smelter, not a second Press** — a second ore
line, which is the thing `artillery` builds and the thing `branched_artillery` measured the price
of. "A player who wants to shoot needs a second production line" was this file's own conclusion
from #26 and it survives #62 intact; what #62 adds is that the line has to start at the **ore**,
because every Press downstream of one Smelter is dividing the same 18.75 plate a minute.

#### 4. A row that fires a ranged weapon can still be seed-invariant

`armed_player` is the **second** row in this table with a distribution in it, and the first
addition to that set since `rifle_picket`: 24m14s, 24m15s and 24m15s, at peak Heat 5447, 5443 and
5443. One second and four units of Heat, which is `Simulation._scatter` — the only consumer of
the seeded RNG in `sim/` — moving where 374 rounds went.

`armed_second_press` fires one too and is **bit-identical on all three seeds** in every figure
the report prints. So firing a ranged weapon is **necessary for a spread and not sufficient**:
133 shots over fourteen minutes are too few to change which Wave lands last. The property this
file states — that a Run length is a function of the Factory and not of the seed — is intact, and
the qualification is sharper than "the rows that fire can spread": a row spreads when it fires
*enough to matter*.

#### What #62 did not change, and one figure it corrected

**No value in `content/` was touched**, which was an acceptance criterion of the ticket rather
than a side effect. Nothing here is an argument for moving one: a player can arm themselves, the
cost to the Turret is legible, and the two numbers most likely to be wrong about shooting are
still `gear.view_kick_degrees_per_shot` and `gear.enemy_hit_radius_metres`, which are about what
a fight feels like through a mouse. `player.starting_stock` stays plate alone and the keystone
loop stays stated correctly.

One measured figure in this file was wrong and is rewritten from the measurement rather than
reconciled with it: the Turrets section said `competent`'s Ammunition stockpile "peaks at 454
rounds around minute twenty-four". It peaks at **446, at minute twenty-three**. The 96 rounds
still in the Factory when the Nest falls is exact.

### What separation cost the table

**#76 made Enemies push one another apart, and fifteen of the seventeen rows moved by at most
three seconds.** The two that moved further are the two that fire a *scattering* weapon at a
crowd, which is the one thing spreading a crowd could be expected to change. Measured on all
three seeds, on the tip, with nothing in `content/` touched.

| Scenario | #62 | **#76** | moved by |
|---|---|---|---|
| `bare` | 3m22s | **3m22s** | — |
| `opening_line` | 3m12s | **3m12s** | — |
| `competent` | 28m48s | **28m51s** | +3s |
| `over_producer` | 20m21s | **20m22s** | +1s |
| `fortified` | 28m45s | **28m48s** | +3s |
| `deep_digger` | 12m27s | **12m28s** | +1s |
| `hive_sortie` | 32m05s | **32m07s** | +2s |
| `rifle_picket` | 27m18s | **25m03s** | **−2m15s** |
| `artillery` | 16m40s | **16m41s** | +1s |
| `second_press` | 24m14s | **24m16s** | +2s |
| `walled_lane` | 28m45s | **28m48s** | +3s |
| `sealed_breach` | 26m42s | **26m41s** | −1s |
| `branched_artillery` | 13m57s | **13m58s** | +1s |
| `deep_silo` | 12m59s | **13m00s** | +1s |
| `coal_haul` | 15m41s | **15m42s** | +1s |
| `armed_player` | 24m14s | **24m14s** | — |
| `armed_second_press` | 14m43s | **14m26s** | −17s |

**The ±3 seconds is the mechanic and not noise.** A crowd that spreads takes marginally longer
to put its damage on the thing it came to eat — the bodies at the back of a press are further
back than they used to be, by about a body's width each — so a Factory that was going to lose
loses a little later. It is the right sign and it is almost nothing, which is the result this
change wanted: separation is a rule about where bodies stand and not about how hard they bite.

**`rifle_picket` lost 2m15s, and the mechanism is worth keeping because it is a general fact
about this game rather than about that row.** An interpenetrating stack was several Crawlers at
*one coordinate*, so a round that missed the one it was aimed at very often hit a neighbour
standing inside it — a `gear.scatter_degrees` of 0.4 on a Bolt Rifle was being paid back by the
pile. Spread them out and a miss is a miss. So **separation makes a crowd a worse target for
anything that scatters**, and that is a real combat consequence of a change made for the look.
**And the probe's own figures are what separate that reading from phase noise**, which is the
thing this row is notorious for. The rifleman's *economy is unchanged*: 468 rounds reached him
against #62's 520, over a Run 2m15s shorter — 18.9 a minute either way, which is the Nest line's
half-share of one Ammo Press to the round. He fired 455 of them against 520, which is the same
18.4 shots a minute. He was **dry for 75% of it against 74%**. Same income, same discipline,
same trigger time — and the Nest falls two minutes sooner with 27 Enemies at the gate. **Nothing
about what he was given or what he did with it moved; only what his rounds bought.** Peak Heat
fell with it, 6051 to 5599, which is the same sentence from the other end: fewer kills, more
Enemies at the gate, less time to make Heat in.

**`competent` did not move for the same reason `competent` never moves on this axis:** a
Turret acquires on an Enemy's *point* against `range_tiles` and resolves against no hit volume
at all (see "What a bigger Breaker cost the table"), so the thing that does nearly all of the
killing in fifteen of these rows cannot tell a spread crowd from a stacked one. Only a
**player's** weapon reads the capsule, and only three rows have one.

**`SAME_LENGTH_SECONDS` widened from 150 to 300**, and it is the first time that constant has
moved for a reason other than phase: 25m03s against 28m51s is 228 seconds. **Widening a guard
until it stops failing is exactly the wrong move and is worth saying out loud**, because #47
doing it once is precedent for the *method* and not a licence — so the test is only still worth
having if the claim it makes is still falsifiable. It is. The band is two-sided and it is not
the Run length: what fails here is a rifleman who **pays for himself** (within a few seconds of
`competent`, or longer than it) or one who is **ruinous** (half the Run, which is where
`armed_second_press` sits at 14m26s and is the shape of the thing this guard exists to catch).
At 300 seconds a rifleman costing 13% of a twenty-nine-minute Run passes and both of those
fail, which is the claim and all of it. If a later change needs 450, the honest response is to
stop asserting a Run length on this row and assert the thing #62 showed it is really about —
rounds that reach the player against rounds he spends. **No value in
`content/` was changed**, which was the ticket's own instruction and is also the honest
reading: this is a measurement of a mechanic, not an argument that a number is wrong.

**And the seed invariance sharpened rather than broke.** Fifteen rows are bit-identical on all
three seeds. `rifle_picket` still spreads — 25m03s, 24m40s and 25m08s, a 28-second band against
#47's 39 — and **`armed_second_press` now spreads where it did not**, 14m26s against 14m35s.
That is #62's own qualification arriving as a measurement: a row spreads when it fires *enough
to matter*, and separation is precisely what makes each of its 133 shots matter more, because a
scatter-miss into a spread crowd now misses. `armed_player` fires 374 shots and is identical on
all three, which is the counter-example that keeps the rule honest.

### What the seed can reach

**A Run length here is a function of the Factory and not of the seed, and that is a property of
the Simulation rather than of the harness.** (#62 added the second row with a spread in it and
also the counter-example that sharpens the rule — see finding 4 under "What #62 measured":
firing a ranged weapon is necessary for a spread and not sufficient.) The Map is handcrafted (`MapLayout.starter()`
consults no seed), the Wave schedule is a function of Heat, and the single consumer of the
seeded RNG in the whole of `sim/` is `Simulation._scatter` — the spread on a *ranged* shot. So
three seeds are three identical Runs — down to which Machines were lost in which order — for
every scenario in which nobody pulls a trigger, and
`test_balance.test_a_run_length_is_a_function_of_the_factory_and_not_of_the_seed` asserts
exactly that on `competent`. `rifle_picket` is the one row that fires, and it is the one row
that has ever spread.

Two consequences worth knowing before anybody quotes a variance:

- **The three seeds in the measurement are a demonstration, not a sample.** There is no
  distribution to sample until a player opens fire — and `rifle_picket` is the one row that
  does. #26 measured it identical across all three seeds; with #30's collision in it was 26m32s
  on seed 7 against 26m29s on seeds 11 and 29; on #35's branch it spread eleven seconds; on the
  merged schedule and through #46 it was identical again at 28m02s. **#47 split it once more**:
  27m18s, 27m20s and 26m39s, a spread of 39 seconds, with peak Heat 6051, 6001 and 5892.

  **#49 re-measured all three seeds and reproduced those six figures exactly** — 27m18s, 27m20s
  and 26m39s at peak Heat 6051, 6001 and 5892 — which is the first time any row of this table
  has been independently re-derived by a later ticket rather than carried forward. **#58 got the
  same six again**, and **#60 a third time** — so the one row with a distribution in it has now
  been reproduced three times by tickets that had no stake in it. A table whose whole value is
  that somebody can re-derive it is worth occasionally re-deriving.

  **And the six rows #60 added are the property's control.** Not one of them fires a player's
  ranged weapon — the two sorties in them carry no gun at all — so every one is identical on all
  three seeds in every figure the table prints, including the Walls built and the hit points they
  absorbed. Six new rows and six times zero spread is what "a Run length is a function of the
  Factory" looks like when it is tested rather than asserted.

  **#62's two rows then split the set in a way that was worth measuring.** Both fire a ranged
  weapon. `armed_player` spreads — 24m14s, 24m15s, 24m15s at peak Heat 5447, 5443, 5443 — which
  makes it the second row in this table with a distribution and the first since `rifle_picket`.
  `armed_second_press` is **bit-identical on all three** in every printed figure, because its
  player fires 133 shots in fourteen minutes and that is too few to change which Wave lands
  last. So the qualification on the property is sharper than "rows that fire can spread": a row
  spreads when it fires *enough to matter*.

  The last paragraph of this bullet used to warn that the spread going to zero was not an
  improvement anybody made and that the next ticket to re-phase the schedule might split the
  seeds again. It did, and the ticket was #47 — which bought the picket's Belt with a lever pull
  and moved the schedule's phase by one Wave. So the warning is now a measurement rather than a
  caution, and the **property** is the thing to hold on to: scatter moves where the rounds go,
  which moves how much Heat the Factory had made by the end and, on a row that fires, when the
  last Wave lands. It does not move how long a Factory that fires nothing stands. The other
  eight rows are bit-identical across all three seeds, and
  `test_balance.test_a_run_length_is_a_function_of_the_factory_and_not_of_the_seed` asserts that
  on `competent`, which is one of them.
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
   is bounded by something the player built rather than by a number in `tuning.toml`. **#47 made
   the half of it that is a decision say itself out loud**: the line costs forty plate and the
   route line quotes the bill beside the length before the drag is released, so "forty tiles to
   deliver twenty coal" is now a visible trade rather than a free one — and `deep_digger` buys that
   line with two pulls of the lever instead of getting it at tick 3, which is what moved the row to
   12m27s. What is still unsaid is the *consequence*: the Belt holds 160 coal before back-pressure
   reaches the Miner, and nothing warns that the Boiler is going to go hungry for as long as it
   fills. That is a HUD ticket. **#60 paid the cheap half and the sign flipped**: the
   demolish-removed variant is `coal_haul`, and on the fair share leaving the line standing is
   **15m41s against 12m27s — three minutes longer**, at 47% of the Run in Power deficit rather
   than 17%. Half the coal keeps the Boiler relighting, and a browned-out Factory is a cool one:
   peak Heat 2488 against 3538. So this is no longer a trap at all, and the HUD ticket's argument
   has to change with it — what the Belt hides is not a tax but a brake. See finding 5 under
   "What #60 measured".
10. **"The Turret ran dry" has to be measured on the Factory, not on the Turret.** A destroyed
   Turret holds no rounds and contributes no ticks, so a per-Turret ratio reports 0% for the
   most common ending there is: the Ammunition ran out, and then the Breakers ate the Turret.
   `DRY_ENDGAME_PERCENT` is measured against "no Ammunition anywhere in the Factory".

### What is still unmeasured

Honest residue, so the next ticket does not have to rediscover it:

- **Anything that is about feel through a mouse.** `gear.view_kick_degrees_per_shot`,
  `gear.enemy_hit_radius_metres`, `silo.paint_seconds`, and whether a player *hesitates* before
  leaving the Factory. A harness has no opinion about any of them.
- **Whether a priced Belt makes routing interesting or makes it fiddly**, which is #47's whole
  bet and the one thing a scripted session cannot have an opinion about. A scenario issues
  `BUILD_BELT` with two tiles; a player drags a route watching a bill climb, and whether that
  reads as a decision or as book-keeping is a question for somebody with a mouse. The two numbers
  to reach for if it reads as book-keeping are the price in `content/structures.csv` and
  `player.starting_stock`, in that order.
- **Whether the declared port reads as a rule or as a mystery.** The arrows have been on screen
  since #36 and now mean something, so a Belt that will not connect is a Belt whose Machine is
  facing the wrong way. **#56 made the HUD say so** — in two different sentences, because a
  wall with no port on it and a wall whose port runs the other way have different fixes — and
  raised the red post at such an end clear of the arrows it was lost in. What is still
  unmeasured is whether that is *enough*: the sentence names rotation, and nothing has watched
  a person read it and reach for right mouse. `test_nest_store` needed exactly that fix to its
  own Factory, which is weak evidence that a person will hit it; there is no evidence either
  way yet that a person told about it gets out.
- **Hand repair under fire.** No scenario picks up a wrench to save a Machine, because chasing a
  Breaker open-loop is not possible. `wrench.repair_points_per_second` against
  `enemy.breaker_damage` is still an arithmetic claim.
- **What a roof is worth, which is #58's residue and the same hole one step along.** Height
  counts now — an Enemy reaches as high as it is tall — and **no scenario ever leaves the
  ground**, so the table confirmed only that the ground case did not move. What is unmeasured is
  whether climbing a Machine to get out of Chaff's reach is a decision or a cheese, and whether
  the Breaker eating the floor out from under a player reads as the right answer or as a
  punishment. Both are about watching rather than about a Run length. The two numbers to reach
  for if it reads as a cheese are the heights themselves, `enemy.enemy_hit_height_metres` and
  `enemy.breaker_hit_height_metres` — which are also what a Breaker *looks* like, so neither can
  be moved for balance without moving what is on screen. That coupling is deliberate (#49) and
  is the thing to argue with before the thing to change.
- **What a bigger Breaker is worth to a player, in both directions**, which is #49's residue.
  It is easier to shoot — a 2.2 m by 0.8 m capsule against the Crawler's 1.6 by 0.6 — and it
  bites from 0.2 m further out, because reach is measured from the hull. Neither showed in the
  table, for the reason given in "What a bigger Breaker cost the table": a Turret resolves on
  the Enemy's point and never on the capsule, and the one scenario that fires a player's weapon
  barely meets a Breaker before it ends. Both are about aiming and spacing through a mouse,
  which is the same category as `gear.enemy_hit_radius_metres` itself.
- ~~**Walls.**~~ **Measured by #60, and the answer is that a Wall in the open is never bitten.**
  `walled_lane` and `sealed_breach` are the two rows; see finding 2 under "What #60 measured".
  What is left unmeasured is the half a harness cannot have an opinion about: whether re-routing a
  Wave through a kill zone *feels* like a defence. Two plates a tile is not what makes a funnel
  worthless — free Walls across that lane would have absorbed the same zero hit points — so the
  price is not the number to reach for if it reads badly.
- **Two of the three Stratagems, and the Painting's length — and #60 moved the *reason* rather
  than closing it.** A Barrage's 150 points over six tiles, a Supply Drop into a player's own
  pockets and `silo.paint_seconds` at five seconds are all still arithmetic. What `deep_silo`
  settled is that the Barrage is **not reachable at all**: it sits behind `t03_deep_survey`'s 400
  plate and 200 coal, which is twenty-one minutes of one Smelter's entire output, and the only Run
  that reaches Depth 2 lasts thirteen. See finding 4 under "What #60 measured".
  **The next scenario worth writing is a `competent` Factory that pays `t02_deep_mining` and then
  builds a Silo** — twenty-eight minutes of Run rather than thirteen, which is the only shape that
  has time to unlock a Supply Drop *and* fill a tube. A Barrage needs a Run nothing in this table
  is close to, so it wants a content decision about `t03_deep_survey`'s bill rather than a
  scenario.
- **Answering a Siege Hulk on foot**, for the flanking reason above — and it is now the single
  biggest hole in the table rather than a footnote. Before #34 no scenario reached 6400 Heat at
  all; now **four of them do**, and all four end with Siege Hulks standing that nothing they own
  can hurt. Every Run over twenty minutes therefore ends the same way, which compresses the
  differences between builds at the top of the table and is a harness limitation rather than a
  balance fault: the Hulk's answer is a player walking behind it, and an open-loop scripted
  session cannot walk a circle around something that is walking towards it. **The next thing a
  human should play is `competent` from minute twenty-five with a rifle in their hands.**
- ~~**A second Ammo Press.**~~ **Measured by #60, and it is a mistake rather than an answer.**
  `second_press` builds the Press *and* the second Turret and is 16% shorter than `competent`,
  ending with 416 rounds nobody could spend — because a Turret's output is bounded by how long an
  Enemy spends inside its 16 m and not by its feed. See finding 1 under "What #60 measured".
  **#62 closed the player half of it too**: `armed_second_press` puts a rifleman on that same
  Factory and is 14m43s with the player dry for 83%, because the second Press halves the only
  Press whose rounds reach the counter. What is still open is the question that replaces both:
  **what a Factory can buy that converts production into kills**, since neither a second feed,
  nor a second gun, nor a player with a rifle does. That is a design question rather than a
  measurement, and `mg_turret_mk1`'s `range_tiles` and `fire_mg`'s rate are where it would be
  answered.
- ~~**Whether a Run can keep a magazine full out of the Nest's store.**~~ **Measured by #62, and
  the answer is yes at burst discipline and no at any other.** `armed_player` is dry for 9% of a
  24m14s Run on the nineteen rounds a minute the Nest's line pays; `rifle_picket` is dry for 74%
  on the same income. See "What #62 measured". What a harness still cannot say is whether
  **eight seconds in forty is what a fight actually costs** — the burst length is a discipline
  imposed by a clock, because a scenario cannot see a Wave coming, so the row spends some of its
  rounds at nothing and a real player would spend them at Crawlers. That error is in the same
  direction as the picket's and about a third of the size, so the 9% is a floor on how dry a
  careful player would be rather than an estimate of it. The thing to watch when somebody plays
  it is whether walking to the counter between Waves reads as a rhythm or as a chore.
- ~~**A branched Factory.**~~ **Measured by #60 as `branched_artillery`, and the mechanic works
  while the saving does not**: thirty-five tiles of Belt to carry plate round to where the Silo
  stands is 35 plate against the 24 a second Miner and Smelter cost, and it parks 104 plate on
  the haul. See finding 3 under "What #60 measured". What is unmeasured is a branch whose
  consumer is *next to* its producer, which is the arrangement the arithmetic assumed and which
  no row has built.
- ~~**Whether a long Belt to the Nest is still a trap, on a fair share.**~~ **Measured by #60 as
  `coal_haul`, and the sign has flipped**: leaving it standing is 3m14s *longer*, because 47% of
  the Run in Power deficit is 30% less peak Heat. See finding 5. What that opens is a question
  nobody asked for: **whether deliberately under-powering a Factory is a strategy**, which is
  about `heat.decay_per_minute` against what a working Factory makes and wants a human.
- **Whether a crowd that presses in rather than interpenetrating reads as a crowd**, which is
  #76's residue and is the half a harness has no opinion about. The geometry is measured — a
  crowd with road ahead settles at exactly tangency and holds, a crowd at the Nest crushes to
  0.82 of the room it wants — and `docs/images/swarm_separation_{before,after}.png` is the
  argument that it looks right in one frame. What no still image settles is whether a Wave
  *arriving* now reads as a crowd in motion or as a looser rank, which is the same category as
  #49's "does the size difference read in motion". The two numbers to reach for if it reads as
  mush are both derived rather than tuned — a kind's `hit_radius`, which is also how big it
  looks, and `_lane_corridor_metres`' two-bodies allowance — so neither can be moved for the
  look without moving what a player shoots at.
- **What the pass costs past a few hundred Enemies, and this is a gap in the instrument rather
  than a measurement.** `tools/visual/enemy_tick_cost.gd` reaches the Chaff tier's numbers by
  removing the Factory, which means nothing kills anything and the whole Wave ends up crushed
  against one Nest — the single worst case the rule has, because a crush is where every pair
  overlaps on every tick and none of them can resolve. No shipped scenario produces it: the
  balance rows end with 15 to 32 Enemies at the gate, not two hundred. A scale figure that is
  honest about a *playable* Factory wants Turrets in it, and then the Turrets decide the
  population rather than the harness.
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
- **The guard reads `SCRIPT ERROR:` and nothing else, so a leak is invisible to it**, and #76
  is where that cost something: `test_world_view.gd`'s last method ended the file without
  `view.free()` and the run reported **177 leaked RIDs at exit** with every test green. A
  suite that passes while leaking is exactly the shape this guard was built for and exactly
  the shape it cannot see — the engine reports a leak as an `ERROR:` at *cleanup*, after the
  runner has already counted its results. Fixed in `5936fc1`; worth knowing that **a view a
  test builds has to be freed by the test that built it**, because nothing will tell you
  otherwise.

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
