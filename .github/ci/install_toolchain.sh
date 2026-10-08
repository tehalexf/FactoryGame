#!/usr/bin/env bash
#
# Put `godot`, `blender` and/or `ffmpeg` on PATH in a CI runner, at the versions
# .github/ci/toolchain.env pins.
#
#   .github/ci/install_toolchain.sh godot
#   .github/ci/install_toolchain.sh blender
#   .github/ci/install_toolchain.sh godot blender ffmpeg
#
# Downloads go to $TOOLCHAIN_CACHE (default ~/.cache/deep-foundry-toolchain) and
# that directory is what actions/cache keeps. The archives total ~590 MB, so a
# fetch on every push would be most of the job's wall clock; on a cache hit this
# script downloads nothing and only unpacks.
#
# Installs land in $TOOLCHAIN_DIR (default ~/.local/opt) with symlinks in
# $TOOLCHAIN_BIN (default ~/.local/bin) — deliberately the same layout as the
# developer machine, so "works in CI" and "works locally" mean the same thing.
#
# Idempotent: an install that is already present and already hashes correctly is
# left alone.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$here/toolchain.env"

TOOLCHAIN_CACHE="${TOOLCHAIN_CACHE:-$HOME/.cache/deep-foundry-toolchain}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$HOME/.local/opt}"
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-$HOME/.local/bin}"
mkdir -p "$TOOLCHAIN_CACHE" "$TOOLCHAIN_DIR" "$TOOLCHAIN_BIN"

say() { printf '  %s\n' "$*"; }

# Verify a file against a sha256, printing what it found when it disagrees.
# A silent corrupt download is how a toolchain install becomes a mystery test
# failure three steps later.
check_sha256() {
	local path="$1" want="$2" got
	got="$(sha256sum "$path" | cut -d' ' -f1)"
	if [ "$got" != "$want" ]; then
		echo "error: $path has sha256 $got, expected $want" >&2
		return 1
	fi
}

# Download $2 into $1, trying each remaining argument as a base URL, and keep
# only bytes that match $3.
fetch_verified() {
	local dest="$1" sha="$2"
	shift 2
	if [ -f "$dest" ] && check_sha256 "$dest" "$sha" 2>/dev/null; then
		say "cached: $(basename "$dest")"
		return 0
	fi
	rm -f "$dest"
	local url
	for url in "$@"; do
		say "fetching $url"
		if curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 30 -o "$dest.part" "$url"; then
			if check_sha256 "$dest.part" "$sha"; then
				mv "$dest.part" "$dest"
				return 0
			fi
			say "checksum mismatch from this host, trying the next"
		else
			say "no answer from this host, trying the next"
		fi
		rm -f "$dest.part"
	done
	echo "error: could not fetch $(basename "$dest") from any host" >&2
	return 1
}

install_godot() {
	local target="$TOOLCHAIN_DIR/$GODOT_BINARY"
	if [ -x "$target" ] && check_sha256 "$target" "$GODOT_BINARY_SHA256" 2>/dev/null; then
		say "godot $GODOT_VERSION already installed"
	else
		local zip="$TOOLCHAIN_CACHE/$GODOT_BINARY.zip"
		fetch_verified "$zip" "$GODOT_ZIP_SHA256" "$GODOT_URL"
		rm -rf "$TOOLCHAIN_CACHE/godot-unpack"
		mkdir -p "$TOOLCHAIN_CACHE/godot-unpack"
		unzip -q -o "$zip" -d "$TOOLCHAIN_CACHE/godot-unpack"
		mv -f "$TOOLCHAIN_CACHE/godot-unpack/$GODOT_BINARY" "$target"
		rm -rf "$TOOLCHAIN_CACHE/godot-unpack"
		chmod +x "$target"
		# The binary, not just the archive. This is the thing that runs 1085
		# tests; it is worth one more hash.
		check_sha256 "$target" "$GODOT_BINARY_SHA256"
	fi
	ln -sfn "$target" "$TOOLCHAIN_BIN/godot"
}

install_blender() {
	local root="$TOOLCHAIN_DIR/$BLENDER_DIRNAME"
	if [ -x "$root/blender" ]; then
		say "blender $BLENDER_VERSION already installed"
	else
		local archive="$TOOLCHAIN_CACHE/$BLENDER_ARCHIVE"
		# shellcheck disable=SC2086
		local urls=()
		local base
		for base in $BLENDER_MIRRORS; do urls+=("$base/$BLENDER_ARCHIVE"); done
		fetch_verified "$archive" "$BLENDER_SHA256" "${urls[@]}"
		rm -rf "$root" "$root.part"
		mkdir -p "$root.part"
		# The tarball's single top-level directory is stripped so the install
		# path is ours rather than the archive's.
		tar -xJf "$archive" -C "$root.part" --strip-components=1
		mv "$root.part" "$root"
	fi
	ln -sfn "$root/blender" "$TOOLCHAIN_BIN/blender"
}

install_ffmpeg() {
	local root="$TOOLCHAIN_DIR/$FFMPEG_DIRNAME"
	if [ -x "$root/bin/ffmpeg" ]; then
		say "ffmpeg $FFMPEG_VERSION already installed"
	else
		local archive="$TOOLCHAIN_CACHE/$FFMPEG_ARCHIVE"
		fetch_verified "$archive" "$FFMPEG_SHA256" "$FFMPEG_URL"
		rm -rf "$root" "$root.part"
		mkdir -p "$root.part"
		tar -xJf "$archive" -C "$root.part" --strip-components=1
		mv "$root.part" "$root"
	fi
	# Both binaries: the tests shell out to ffprobe as well as ffmpeg, and a
	# half-installed pair is a confusing skip rather than a clear error.
	ln -sfn "$root/bin/ffmpeg" "$TOOLCHAIN_BIN/ffmpeg"
	ln -sfn "$root/bin/ffprobe" "$TOOLCHAIN_BIN/ffprobe"
}

if [ "$#" -eq 0 ]; then
	echo "usage: $(basename "$0") [godot] [blender]" >&2
	exit 2
fi

for what in "$@"; do
	case "$what" in
		godot) echo "== godot $GODOT_VERSION"; install_godot ;;
		blender) echo "== blender $BLENDER_VERSION"; install_blender ;;
		ffmpeg) echo "== ffmpeg $FFMPEG_VERSION"; install_ffmpeg ;;
		*) echo "error: unknown tool '$what'" >&2; exit 2 ;;
	esac
done

# GitHub Actions only: make the symlinks visible to every later step.
if [ -n "${GITHUB_PATH:-}" ]; then
	echo "$TOOLCHAIN_BIN" >> "$GITHUB_PATH"
fi

export PATH="$TOOLCHAIN_BIN:$PATH"
echo "== versions on PATH"
for what in "$@"; do
	case "$what" in
		godot) godot --version ;;
		blender) blender --version | head -1 ;;
		ffmpeg) ffmpeg -version | head -1 ;;
	esac
done
