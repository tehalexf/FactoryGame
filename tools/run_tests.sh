#!/usr/bin/env bash
#
# Run the DEEP FOUNDRY test suite headless. This is the one-line CI command.
#
#   tools/run_tests.sh              # whole suite
#   tools/run_tests.sh determinism  # only tests whose case.method contains it
#
# Exits 0 when green, non-zero otherwise.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: '$GODOT' not found on PATH. Set GODOT=/path/to/godot." >&2
	exit 127
fi

# Always rescan before running. `class_name` globals resolve through
# .godot/global_script_class_cache.cfg, which only an import pass rebuilds — so a
# newly added class would otherwise fail with a baffling "Identifier not declared
# in the current scope" instead of running. One extra engine start is cheap
# insurance against that.
#
# Twice on a cold cache, and this is not superstition. One pass imports the glTF
# files; the scenes Godot *derives* from them are not necessarily resolvable
# until a pass that starts with those imports already in place. With a single
# pass the Machine-mesh tests failed roughly one cold run in four — green on a
# warm cache, red on a fresh clone, which is the worst shape a test failure can
# have. The second pass is a no-op when the cache is warm.
#
# Two is also *enough*, which has now been measured rather than assumed:
# checksumming the whole of `.godot/` after each of four consecutive cold passes
# shows pass 1 → 2 changing one editor bookkeeping file and 2 → 3 → 4 changing
# nothing at all. A third pass would buy nothing.
#
# Decided before anything below can create `.godot`, because the *absence* of
# that directory is what "cold" means here.
IMPORT_PASSES=1
if [ ! -d "$PROJECT_ROOT/.godot" ]; then
	IMPORT_PASSES=2
fi

# Give this worktree its own `user://`.
#
# Godot derives the user data directory from the project's *name*, so every
# worktree of this repo resolves `user://` to one shared directory under
# ~/.local/share/godot/app_userdata/. That has now bitten this project twice.
# The first time it was the engine log, fixed below by naming a private log file.
# The second time it was the test fixtures that write there: the Definition
# Watcher's tests create `user://definition_watcher_test` in `before_each` and
# delete it in `after_each`, and the Run-save tests write a save file, so a
# sibling checkout running its suite deletes the directory out from under this
# one between its `make_dir` and its `store_string`. The symptom was four
# failures in test_definition_watcher — "Cannot call method 'store_string' on a
# null value" — that did not reproduce on a re-run, because by then the sibling
# had finished.
#
# Fixing it per-fixture would fix it only for the fixtures that exist today, so
# the whole of `user://` moves instead. On Linux Godot resolves the user data
# directory under $XDG_DATA_HOME, so pointing that at `.godot/` — already
# per-worktree, already ignored by git and by Godot's own importer — makes every
# `user://` path in the suite private to this run. It also means `rm -rf .godot`
# clears leftover test state, which is the behaviour a cold run should have.
export XDG_DATA_HOME="$PROJECT_ROOT/.godot/userdata"

# Import, and insist that it actually happened.
#
# `godot --import` is not reliable on a cold cache: under concurrent load it
# segfaults in the audio importer in roughly one cold pass in forty, part way
# through, leaving `.godot/` with a handful of files instead of the seven-hundred
# odd a finished import writes. This used to be discarded with `|| true` and the
# suite ran anyway — against a cache with no imported Machine meshes in it, which
# reports as eight mystery failures in test_machine_meshes, test_world_view and
# test_game_audio, all of which pass on a re-run because the next pass finishes
# the import. A crashed import must be retried, and a suite must never run
# against a cache nobody checked.
import_once() {
	local label="$1"
	local output status
	output="$(mktemp)"
	set +e
	"$GODOT" --headless --path "$PROJECT_ROOT" --import >"$output" 2>&1
	status=$?
	set -e
	if [ "$status" -eq 0 ]; then
		rm -f "$output"
		return 0
	fi
	echo "warning: import $label exited $status; the cache may be half-built." >&2
	tail -5 "$output" >&2 || true
	rm -f "$output"
	return 1
}

# Every asset the project declares an import for must have its imported product
# on disk. This is the cache check the segfault above needs: a pass that died
# half way leaves most of `dest_files` unwritten, and that is exactly what the
# eight failures were reading.
#
# Directories whose name begins with `.`, and anything under a `.gdignore`, are
# skipped because Godot's own importer skips them — `content/` and
# `assets_licensed/` are both deliberately outside the importer's reach, and a
# nested worktree under `.claude/` is not this project's business.
unimported_count=0
unimported_example=""
verify_import() {
	unimported_count=0
	unimported_example=""

	local ignored=()
	local marker
	while IFS= read -r marker; do
		ignored+=("${marker%.gdignore}")
	done < <(find "$PROJECT_ROOT" -name '.*' -type d -prune -o -name .gdignore -print 2>/dev/null)

	local sidecars=()
	local sidecar prefix skip
	while IFS= read -r sidecar; do
		skip=0
		for prefix in "${ignored[@]}"; do
			case "$sidecar" in "$prefix"*) skip=1 ;; esac
		done
		if [ "$skip" -eq 0 ]; then
			sidecars+=("$sidecar")
		fi
	done < <(find "$PROJECT_ROOT" -name '.*' -type d -prune -o -name '*.import' -print 2>/dev/null)

	if [ "${#sidecars[@]}" -eq 0 ]; then
		return 0
	fi

	# One awk over every sidecar, emitting "<sidecar>\t<declared destination>".
	local source dest disk
	while IFS=$'\t' read -r source dest; do
		disk="$PROJECT_ROOT/${dest#res://}"
		if [ ! -f "$disk" ]; then
			unimported_count=$((unimported_count + 1))
			if [ -z "$unimported_example" ]; then
				unimported_example="$dest, declared by ${source#"$PROJECT_ROOT"/}"
			fi
		fi
	done < <(awk '
		/^dest_files=\[/ {
			rest = $0
			while (match(rest, /"res:\/\/[^"]*"/)) {
				dest = substr(rest, RSTART + 1, RLENGTH - 2)
				print FILENAME "\t" dest
				rest = substr(rest, RSTART + RLENGTH)
			}
		}
	' "${sidecars[@]}")

	[ "$unimported_count" -eq 0 ]
}

# Two spare attempts per pass. A pass that crashes and is retried has not been
# seen to crash again — the retry starts with most of the import already done, so
# it has far less left to crash in.
IMPORT_ATTEMPTS_PER_PASS=3
import_pass() {
	local label="$1"
	local attempt=1
	until import_once "$label"; do
		attempt=$((attempt + 1))
		if [ "$attempt" -gt "$IMPORT_ATTEMPTS_PER_PASS" ]; then
			echo "error: 'godot --import' failed $IMPORT_ATTEMPTS_PER_PASS times in a row." >&2
			return 1
		fi
		echo "         retrying import ($attempt/$IMPORT_ATTEMPTS_PER_PASS)..." >&2
	done
	return 0
}

for pass in $(seq "$IMPORT_PASSES"); do
	if ! import_pass "pass $pass/$IMPORT_PASSES"; then
		echo "       Refusing to run the suite against a half-built .godot/ —" >&2
		echo "       it would report the missing imports as unrelated test" >&2
		echo "       failures. Try 'rm -rf .godot' and run again." >&2
		exit 2
	fi
done

# Verification is the authority, not the exit status: a pass can exit 0 and still
# have left something unimported. One more pass if it is unhappy, then give up
# loudly rather than hand the suite a cache nobody vouched for.
if ! verify_import; then
	echo "warning: $unimported_count declared imports are still missing from" >&2
	echo "         .godot/ (e.g. $unimported_example)." >&2
	echo "         Importing once more." >&2
	if ! import_pass "repair pass"; then
		exit 2
	fi
	if ! verify_import; then
		echo "error: the import is incomplete — $unimported_count declared imports are" >&2
		echo "       missing from .godot/, e.g. $unimported_example" >&2
		echo "       Running the suite now would report that as failures in" >&2
		echo "       test_machine_meshes, test_world_view and test_game_audio" >&2
		echo "       rather than as the missing imports they are." >&2
		echo "       Try 'rm -rf .godot' and run again." >&2
		exit 2
	fi
fi

# Give this run its own log file.
#
# The runtime-abort guard reads the engine's log to notice a test method severed
# by a GDScript error. The default log lives under the *user data* directory,
# which is now per-worktree (above) — but naming the file explicitly is kept
# because it also keeps the log out of the rotation the import passes drive, and
# because the guard's liveness probe is clearer when it knows the exact path.
#
# .godot/ is per-worktree and already ignored, so a log in there is private to
# this run.
TEST_LOG="$PROJECT_ROOT/.godot/test_run.log"
mkdir -p "$(dirname "$TEST_LOG")"
rm -f "$TEST_LOG"
export DEEP_FOUNDRY_TEST_LOG="$TEST_LOG"

exec "$GODOT" --headless --path "$PROJECT_ROOT" --log-file "$TEST_LOG" \
	--script res://tests/run_tests.gd -- "$@"
