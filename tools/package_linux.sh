#!/usr/bin/env bash
# Reproducible Linux x86_64 release workflow (not a bit-for-bit reproducible binary).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=4.5.1
GODOT_BIN=${GODOT_BIN:-godot}
CMAKE_BIN=${CMAKE_BIN:-cmake}
JOBS=${JOBS:-3}
CACHE="$ROOT/.cache/package-linux"
BUILD="$ROOT/build-package-linux"
mkdir -p "$CACHE" "$ROOT/dist"
# Version checks also initialize font caches; keep all editor state writable/local.
export XDG_DATA_HOME="$CACHE/editor-data"
export XDG_CACHE_HOME="$CACHE/editor-cache"
export XDG_CONFIG_HOME="$CACHE/editor-config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
for tool in curl unzip python3 tar rg sha512sum objdump; do command -v "$tool" >/dev/null; done
case "$("$GODOT_BIN" --version)" in "$VERSION.stable."*) ;; *) echo "Godot $VERSION stable is required" >&2; exit 1;; esac
if [[ $(uname -m) != x86_64 ]]; then echo 'This workflow targets Linux x86_64.' >&2; exit 1; fi

ARCHIVE="Godot_v${VERSION}-stable_export_templates.tpz"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
if [[ ! -f "$CACHE/$ARCHIVE" ]]; then
  curl -fLsS --retry 2 -o "$CACHE/$ARCHIVE.part" "$BASE/$ARCHIVE"
  mv "$CACHE/$ARCHIVE.part" "$CACHE/$ARCHIVE"
fi
curl -fLsS --retry 2 -o "$CACHE/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
awk -v name="$ARCHIVE" '$2 == name {print; found=1} END {if (!found) exit 1}' "$CACHE/SHA512-SUMS.txt" > "$CACHE/selected.sha512"
(cd "$CACHE" && sha512sum -c selected.sha512)

# Only Linux files are extracted; the entire official archive is verified above.
# Keep editor export templates/cache separate from the player's profile.
TEMPLATES="$XDG_DATA_HOME/godot/export_templates/$VERSION.stable"
mkdir -p "$TEMPLATES" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
unzip -joq "$CACHE/$ARCHIVE" templates/linux_release.x86_64 templates/linux_debug.x86_64 templates/version.txt -d "$TEMPLATES"

CPP_ARGS=("-DSB_GODOTCPP_DIR=")
CPP_SOURCE="$BUILD/_deps/godotcpp-src"
if [[ -f "$ROOT/build/_deps/godotcpp-src/CMakeLists.txt" ]] &&
   [[ $(git -C "$ROOT/build/_deps/godotcpp-src" rev-parse HEAD) == $(git -C "$ROOT/build/_deps/godotcpp-src" rev-parse godot-4.5-stable) ]] &&
   git -C "$ROOT/build/_deps/godotcpp-src" diff --quiet HEAD; then
  CPP_ARGS=("-DSB_GODOTCPP_DIR=$ROOT/build/_deps/godotcpp-src")
  CPP_SOURCE="$ROOT/build/_deps/godotcpp-src"
fi
# Godot's editor imports with the debug library even for a release export.
# Reuse an existing configured debug build; otherwise create an independent one.
DEBUG_BUILD="$ROOT/build-package-debug"
if [[ -f "$ROOT/build/CMakeCache.txt" ]] && rg -q '^GODOTCPP_TARGET:STRING=template_debug$' "$ROOT/build/CMakeCache.txt"; then
  DEBUG_BUILD="$ROOT/build"
else
  "$CMAKE_BIN" -S "$ROOT" -B "$DEBUG_BUILD" -DCMAKE_BUILD_TYPE=Release -DSB_BUILD_GDEXTENSION=ON -DSB_BUILD_TESTS=OFF -DSB_BUILD_APPS=OFF -DGODOTCPP_TARGET=template_debug "${CPP_ARGS[@]}"
fi
"$CMAKE_BIN" --build "$DEBUG_BUILD" --parallel "$JOBS" --target softbodydriver_gd
"$CMAKE_BIN" -S "$ROOT" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DSB_BUILD_GDEXTENSION=ON -DSB_BUILD_TESTS=OFF -DSB_BUILD_APPS=OFF -DGODOTCPP_TARGET=template_release "${CPP_ARGS[@]}"
"$CMAKE_BIN" --build "$BUILD" --parallel "$JOBS" --target softbodydriver_gd

# A unique output directory preserves older packages and any user-created files.
STAGE=$(mktemp -d "$ROOT/dist/linux-stage.XXXXXX")
PACKAGE="$STAGE/SoftBodyDriver-linux-x64"
mkdir -p "$PACKAGE/licenses"
"$GODOT_BIN" --headless --path "$ROOT/game" --editor --import > "$STAGE/import.log" 2>&1
"$GODOT_BIN" --headless --path "$ROOT/game" --export-release Linux "$PACKAGE/SoftBodyDriver.x86_64" > "$STAGE/export.log" 2>&1
if rg -n 'SCRIPT ERROR:|^ERROR:' "$STAGE/import.log" "$STAGE/export.log"; then
  echo "Import/export errors; see $STAGE" >&2; exit 1
fi
cp "$ROOT/LICENSE" "$PACKAGE/LICENSE.txt"
cp "$ROOT/game/ASSET_CREDITS.md" "$PACKAGE/ASSET_CREDITS.md"
cp "$ROOT/game/models/carconcept/LICENSE.md" "$PACKAGE/licenses/CarConcept.md"
cp "$CPP_SOURCE/LICENSE.md" "$PACKAGE/licenses/godot-cpp.txt"
curl -fLsS --retry 2 -o "$PACKAGE/licenses/Godot-LICENSE.txt" "https://raw.githubusercontent.com/godotengine/godot/$VERSION-stable/LICENSE.txt"
curl -fLsS --retry 2 -o "$PACKAGE/licenses/Godot-COPYRIGHT.txt" "https://raw.githubusercontent.com/godotengine/godot/$VERSION-stable/COPYRIGHT.txt"
curl -fLsS --retry 2 -o "$PACKAGE/licenses/nlohmann-json.txt" "https://raw.githubusercontent.com/nlohmann/json/v3.11.3/LICENSE.MIT"
cat > "$PACKAGE/START.txt" <<'TXT'
SoftBodyDriver — Linux x86_64 development build

Extract the entire folder and run ./SoftBodyDriver.x86_64. Keep the shared
library alongside the executable. Godot/editor/source checkout is not needed.
For older graphics drivers: ./SoftBodyDriver.x86_64 --rendering-method gl_compatibility
F1 opens the control guide. Settings and progress are stored in the OS user
data directory for SoftBodyDriver, outside this package.

This is a development build. Passing the bundled packaging smoke check does
not certify GPU performance, a complete driving session, or all product targets.
Asset attribution and third-party licenses are included in this folder.
TXT
python3 "$ROOT/tools/package_smoke.py" "$PACKAGE" "$STAGE"
python3 - "$ROOT" "$PACKAGE" "$CPP_SOURCE" <<'PY'
import hashlib, json, pathlib, platform, re, subprocess, sys
root, package, cpp_source = map(pathlib.Path, sys.argv[1:])
symbols = '\n'.join(subprocess.check_output(['objdump', '-T', str(p)], text=True) for p in package.rglob('*.so'))
glibc_versions = sorted(set(re.findall(r'GLIBC_([0-9.]+)', symbols)), key=lambda v: tuple(map(int, v.split('.'))))
manifest = {
    'godot': '4.5.1-stable', 'platform': 'linux-x86_64',
    'godot_cpp_commit': subprocess.check_output(['git', '-C', str(cpp_source), 'rev-parse', 'HEAD'], text=True).strip(),
    'commit': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
    'working_tree_dirty': bool(subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True)),
    'build_system': platform.platform(),
    'build_libc': platform.libc_ver(),
    'native_library_max_glibc_symbol': glibc_versions[-1] if glibc_versions else None,
    'validation': 'standalone headless menu and gameplay smoke passed; visual/gamepad/performance acceptance separate',
    'files': {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(package.rglob('*')) if p.is_file()},
}
(package / 'BUILD_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
tar -C "$STAGE" -czf "$STAGE/SoftBodyDriver-linux-x64.tar.gz" SoftBodyDriver-linux-x64
sha256sum "$STAGE/SoftBodyDriver-linux-x64.tar.gz" > "$STAGE/SoftBodyDriver-linux-x64.tar.gz.sha256"
echo "Validated package: $STAGE/SoftBodyDriver-linux-x64.tar.gz"
