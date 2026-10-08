#!/usr/bin/env bash
#
# Run one of the three suites and account for every test that skipped.
#
#   .github/ci/run_suite.sh "the tuning dashboard" bash tools/tuning/run_tests.sh
#
# Why this wrapper exists, rather than calling the suite directly:
#
# Two of the three suites skip themselves when a tool is missing, which is the
# right behaviour on a developer machine and a trap in CI. A runner without
# Blender does not fail the asset suite — it drops two whole test modules at
# import time and reports OK, and the job goes green having tested a third less
# than it looks like it tested. That is the same class of bug as a suite that
# never runs at all, which is what this workflow was added to fix, so the fix
# would be half a fix if the skips stayed invisible.
#
# So: every skip is printed as a group, counted by reason, and written to the
# job summary. And a skip for a reason .github/ci/expected_skips.txt does not
# list fails the job. CI provisions Godot, Blender and ffmpeg precisely so that
# the only honest skips left are the ones no runner can satisfy; a new skip
# reason means either a new unmet dependency or a tool that silently went
# missing, and both are things somebody has to look at.
set -uo pipefail

label="${1:?usage: run_suite.sh <label> <command...>}"
shift

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
allowed_file="$here/expected_skips.txt"

log="$(mktemp -t suite-XXXXXX.log)"
trap 'rm -f "$log"' EXIT

echo "::group::$label — full output"
set -o pipefail
"$@" 2>&1 | tee "$log"
status=$?
echo "::endgroup::"

# Python rather than grep because the reason is a quoted tail on a line whose
# head is a test id, and unittest wraps a docstring'd test's id onto the line
# before it. Counting by reason is the useful shape anyway.
python3 - "$log" "$allowed_file" "$label" <<'PY'
import collections, os, re, sys

log_path, allowed_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(log_path, encoding="utf-8", errors="replace").read()

# unittest -v writes "<test id> ... skipped 'reason'", and for a test with a
# docstring the id and the "..." land on separate lines. Either way the reason
# is the quoted string after the word "skipped".
reasons = re.findall(r"skipped\s+'((?:[^'\\]|\\.)*)'", text)
counts = collections.Counter(reasons)

allowed = []
if os.path.exists(allowed_path):
    for line in open(allowed_path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            allowed.append(line)

print()
print(f"--- {label}: skipped tests ---")
if not counts:
    print("nothing skipped — every test in this suite ran.")
else:
    for reason, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        ok = any(pat in reason for pat in allowed)
        print(f"  {n:4d}  {'expected' if ok else 'UNEXPECTED'}  {reason}")

unexpected = {r: n for r, n in counts.items()
              if not any(pat in r for pat in allowed)}

summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a", encoding="utf-8") as fh:
        fh.write(f"### {label}\n\n")
        if not counts:
            fh.write("Nothing skipped — every test in this suite ran.\n\n")
        else:
            fh.write("| Tests | Skipped because | |\n|---:|---|---|\n")
            for reason, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
                ok = any(pat in reason for pat in allowed)
                fh.write(f"| {n} | {reason} | {'expected' if ok else '**unexpected**'} |\n")
            fh.write("\n")

for reason, n in unexpected.items():
    print(f"::error title=Unexpected skip in CI::{label}: {n} test(s) skipped "
          f"with reason {reason!r}. CI is meant to be able to run these. Either "
          f"install what they need, or add the reason to "
          f".github/ci/expected_skips.txt with a note saying why CI cannot.")

sys.exit(1 if unexpected else 0)
PY
audit=$?

if [ "$status" -ne 0 ]; then
	echo "::error title=$label failed::the suite exited $status"
	exit "$status"
fi
exit "$audit"
