#!/usr/bin/env python3
"""Build/run the native chassis rig and retain machine/source/artifact provenance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build-stability")
    parser.add_argument("--output", type=Path, default=ROOT / "build-stability" / "measurements")
    parser.add_argument("--mode", choices=("tow", "coast", "powered"), default="tow")
    parser.add_argument("--cmake", default="cmake")
    parser.add_argument("--jobs", default=4, type=int)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    args.build_dir = args.build_dir.resolve()
    args.output = args.output.resolve()
    if not args.skip_build:
        subprocess.run([args.cmake, "-S", str(ROOT), "-B", str(args.build_dir),
                        "-DCMAKE_BUILD_TYPE=Release", "-DSB_BUILD_APPS=ON", "-DSB_BUILD_TESTS=OFF",
                        "-DSB_BUILD_GDEXTENSION=OFF"], check=True)
        subprocess.run([args.cmake, "--build", str(args.build_dir), "--config", "Release", "--target", "stabilitybench",
                        "--parallel", str(args.jobs)], check=True)
    executable = args.build_dir / "apps" / "sbsim" / ("stabilitybench.exe" if os.name == "nt" else "stabilitybench")
    if not executable.exists():
        executable = executable.parent / "Release" / executable.name
    subprocess.run([str(executable), "--self-test"], check=True)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    args.output.mkdir(parents=True, exist_ok=True)
    sources = [ROOT / "apps/sbsim/stabilitybench.cpp", ROOT / "apps/sbsim/stability_metrics.hpp",
               Path(__file__).resolve()]
    for directory in ("core/include", "core/src", "game/cars"):
        sources.extend(p for p in (ROOT / directory).rglob("*") if p.is_file())
    cpu = platform.processor()
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        cpu = next((line.partition(":")[2].strip() for line in cpuinfo.read_text().splitlines()
                    if line.startswith("model name")), cpu)
    manifest = {"recorded_utc": datetime.now(timezone.utc).isoformat(), "git_revision": revision,
                "working_tree_modified": dirty, "platform": platform.platform(), "cpu": cpu,
                "logical_cpu_count": os.cpu_count(), "executable_sha256": sha256(executable),
                "sources_sha256": {str(p.relative_to(ROOT)): sha256(p) for p in sorted(sources)},
                "note": "Native numerical measurement; concurrent system load is not controlled; not a GPU/performance benchmark."}
    command = [str(executable), "--cars-dir", str(ROOT / "game/cars"), "--output", str(args.output),
               "--mode", args.mode, "--revision", revision + ("+worktree" if dirty else "")]
    manifest["command"] = command
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (args.output / "run.log").write_text(result.stdout)
    print(result.stdout, end="")
    manifest["exit_code"] = result.returncode
    manifest["artifacts_sha256"] = {p.name: sha256(p) for p in sorted(args.output.iterdir())
                                     if p.is_file() and p.suffix in (".csv", ".json", ".log") and p.name != "manifest.json"}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Measurement artifacts: {args.output}")
    return result.returncode

if __name__ == "__main__":
    sys.exit(main())
