#!/usr/bin/env python3
"""Execute the build portion of release-mystical-gsi2.yml outside GitHub Actions.

Intended for a free Google Colab Linux runtime. Release/upload/report steps are
not executed; resulting archives are copied to --output.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML is required: python3 -m pip install pyyaml")

STOP_STEP = "Release mysticalos-gsi-2"


def read_env_file(path: Path, env: dict[str, str]) -> None:
    if not path.exists():
        return
    for raw in path.read_text().splitlines():
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        if key and key.replace("_", "").isalnum():
            env[key] = value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workflow", default=".github/workflows/release-mystical-gsi2.yml")
    parser.add_argument("--output", default="out/gsi2")
    parser.add_argument("--from-step", type=int, default=1, help="1-based run-step index")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    workflow = root / args.workflow
    document = yaml.safe_load(workflow.read_text())
    job = document["jobs"]["mystical2"]
    env = os.environ.copy()
    for key, value in job.get("env", {}).items():
        rendered = str(value)
        if "${{" in rendered:
            rendered = ""
        env[str(key)] = rendered
    env_file = Path(tempfile.mkstemp(prefix="gsi2-env-")[1])
    env.update({
        "GITHUB_WORKSPACE": str(root),
        "GITHUB_ENV": str(env_file),
        "GITHUB_REPOSITORY": "local/colab",
        "GITHUB_SHA": "local-colab",
        "GITHUB_RUN_ID": "local",
    })

    run_index = 0
    for step in job["steps"]:
        if "run" not in step:
            continue
        name = str(step.get("name", f"step-{run_index + 1}"))
        if name.startswith(STOP_STEP):
            break
        run_index += 1
        if run_index < args.from_step:
            print(f"SKIP [{run_index}] {name}", flush=True)
            continue
        print(f"\n===== [{run_index}] {name} =====", flush=True)
        script = tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False)
        script.write("#!/usr/bin/env bash\n")
        script.write(str(step["run"]))
        script.close()
        os.chmod(script.name, 0o700)
        proc = subprocess.run(["bash", script.name], cwd=root, env=env)
        os.unlink(script.name)
        read_env_file(env_file, env)
        if proc.returncode:
            print(f"FAILED: step {run_index} ({name}), rc={proc.returncode}", file=sys.stderr)
            return proc.returncode

    output = root / args.output
    output.mkdir(parents=True, exist_ok=True)
    copied = 0
    for source in (Path("/tmp/MysticalOS_GSI2.tar.gz"), Path("/tmp/MysticalOS_GSI2.zip")):
        if source.is_file():
            shutil.copy2(source, output / source.name)
            copied += 1
    if not copied:
        print("Build steps ended but no GSI2 archives were found", file=sys.stderr)
        return 2
    checksums = output / "SHA256SUMS.txt"
    subprocess.run(["sha256sum", *[p.name for p in sorted(output.glob("MysticalOS_GSI2.*"))]],
                   cwd=output, check=True, stdout=checksums.open("w"))
    print(f"\nDONE: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
