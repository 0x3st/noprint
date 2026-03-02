#!/usr/bin/env python3
"""
Minimal local launcher for multi-profile anti-detect Chromium workflows.
"""

from __future__ import annotations

import argparse
import copy
import json
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"JSON file not found: {path}")
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def resolve_profile_path(profile: str, project_root: Path) -> Path:
    p = Path(profile)
    if p.suffix == ".json" and p.exists():
        return p.resolve()

    candidates = [
        project_root / "configs" / "profiles" / f"{profile}.json",
        project_root / "configs" / "profiles" / profile,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    if p.exists():
        return p.resolve()
    raise FileNotFoundError(
        f"Cannot resolve profile '{profile}'. "
        f"Expected a file path or configs/profiles/{profile}.json"
    )


def load_extensions(shared_extensions_dir: Path) -> list[Path]:
    if not shared_extensions_dir.exists() or not shared_extensions_dir.is_dir():
        return []

    exts: list[Path] = []
    for child in sorted(shared_extensions_dir.iterdir()):
        manifest = child / "manifest.json"
        if child.is_dir() and manifest.exists():
            exts.append(child.resolve())
    return exts


def normalize_path(value: str | None, base: Path) -> Path | None:
    if not value:
        return None
    p = Path(value)
    if not p.is_absolute():
        p = base / p
    return p.resolve()


def resolve_launch_context(
    global_conf: dict[str, Any],
    profile_conf: dict[str, Any],
    profile_path: Path,
    project_root: Path,
) -> tuple[Path, Path, list[Path]]:
    chromium_path_raw = global_conf.get("chromium_path")
    if not chromium_path_raw:
        raise ValueError("global.chromium_path is required")
    chromium_path = normalize_path(chromium_path_raw, project_root)
    assert chromium_path is not None
    if not chromium_path.exists():
        raise FileNotFoundError(f"chromium_path does not exist: {chromium_path}")

    base_data_dir = normalize_path(global_conf.get("base_data_dir", "data"), project_root)
    assert base_data_dir is not None

    profile_id = profile_conf.get("id") or profile_path.stem
    user_data_dir = normalize_path(profile_conf.get("user_data_dir"), project_root)
    if user_data_dir is None:
        user_data_dir = (base_data_dir / profile_id).resolve()
    user_data_dir.mkdir(parents=True, exist_ok=True)

    shared_ext_dir = normalize_path(global_conf.get("shared_extensions_dir"), project_root)
    extensions: list[Path] = []
    if shared_ext_dir is not None:
        extensions = load_extensions(shared_ext_dir)

    return chromium_path, user_data_dir, extensions


def build_launch_command(
    chromium_path: Path,
    user_data_dir: Path,
    extensions: list[Path],
    global_conf: dict[str, Any],
    profile_conf: dict[str, Any],
    runtime_config_path: Path,
) -> list[str]:
    cmd = [str(chromium_path), f"--user-data-dir={user_data_dir}"]

    proxy = profile_conf.get("proxy") or {}
    proxy_server = proxy.get("server")
    proxy_bypass = proxy.get("bypass_list")
    if proxy_server:
        cmd.append(f"--proxy-server={proxy_server}")
    if proxy_bypass:
        cmd.append(f"--proxy-bypass-list={proxy_bypass}")

    if extensions:
        csv = ",".join(str(p) for p in extensions)
        cmd.append(f"--disable-extensions-except={csv}")
        cmd.append(f"--load-extension={csv}")

    # Pass a normalized runtime config to the Chromium patch layer.
    cmd.append(f"--antidetect-config={runtime_config_path}")

    for arg in global_conf.get("chromium_args", []):
        cmd.append(str(arg))
    for arg in profile_conf.get("chromium_args", []):
        cmd.append(str(arg))

    start_url = profile_conf.get("start_url")
    if start_url:
        cmd.append(str(start_url))

    return cmd


def build_runtime_config(
    global_conf: dict[str, Any],
    profile_conf: dict[str, Any],
    profile_path: Path,
    user_data_dir: Path,
) -> dict[str, Any]:
    profile_id = profile_conf.get("id") or profile_path.stem
    config: dict[str, Any] = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "profile_id": profile_id,
        "source_profile_path": str(profile_path),
        "user_data_dir": str(user_data_dir),
        "proxy": copy.deepcopy(profile_conf.get("proxy", {})),
        "fingerprint": copy.deepcopy(profile_conf.get("fingerprint", {})),
        "startup": {
            "global_chromium_args": copy.deepcopy(global_conf.get("chromium_args", [])),
            "profile_chromium_args": copy.deepcopy(profile_conf.get("chromium_args", [])),
            "start_url": profile_conf.get("start_url"),
        },
    }
    return config


def write_runtime_config(user_data_dir: Path, runtime_config: dict[str, Any]) -> Path:
    out_dir = user_data_dir / "antidetect"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "runtime_config.json"
    tmp_path = out_dir / ".runtime_config.json.tmp"
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(runtime_config, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    tmp_path.replace(out_path)
    return out_path.resolve()


def validate_config(
    global_conf: dict[str, Any], profile_conf: dict[str, Any], project_root: Path
) -> list[str]:
    problems: list[str] = []

    if not global_conf.get("chromium_path"):
        problems.append("Missing required field in global config: chromium_path")
    else:
        cp = normalize_path(global_conf.get("chromium_path"), project_root)
        if cp and not cp.exists():
            problems.append(f"chromium_path does not exist: {cp}")

    sed = global_conf.get("shared_extensions_dir")
    if sed:
        sed_path = normalize_path(sed, project_root)
        if sed_path and not sed_path.exists():
            problems.append(f"shared_extensions_dir does not exist: {sed_path}")

    proxy = profile_conf.get("proxy")
    if proxy is not None and not isinstance(proxy, dict):
        problems.append("profile.proxy must be an object")
    if isinstance(proxy, dict) and "server" in proxy and not isinstance(proxy["server"], str):
        problems.append("profile.proxy.server must be a string")

    for key in ("chromium_args",):
        val = global_conf.get(key)
        if val is not None and not isinstance(val, list):
            problems.append(f"global.{key} must be an array")
        val = profile_conf.get(key)
        if val is not None and not isinstance(val, list):
            problems.append(f"profile.{key} must be an array")

    fingerprint = profile_conf.get("fingerprint")
    if fingerprint is not None and not isinstance(fingerprint, dict):
        problems.append("profile.fingerprint must be an object")

    return problems


def command_validate(args: argparse.Namespace, project_root: Path) -> int:
    global_conf = load_json(Path(args.global_config).resolve())
    profile_path = resolve_profile_path(args.profile, project_root)
    profile_conf = load_json(profile_path)

    problems = validate_config(global_conf, profile_conf, project_root)
    if problems:
        print("INVALID CONFIG")
        for p in problems:
            print(f"- {p}")
        return 1

    print("CONFIG OK")
    return 0


def command_list_extensions(args: argparse.Namespace, project_root: Path) -> int:
    global_conf = load_json(Path(args.global_config).resolve())
    shared_dir = normalize_path(global_conf.get("shared_extensions_dir"), project_root)
    if shared_dir is None:
        print("No shared_extensions_dir configured")
        return 0

    extensions = load_extensions(shared_dir)
    if not extensions:
        print(f"No extensions found in: {shared_dir}")
        return 0

    print(f"Extensions in {shared_dir}:")
    for ext in extensions:
        print(f"- {ext}")
    return 0


def command_launch(args: argparse.Namespace, project_root: Path) -> int:
    global_conf = load_json(Path(args.global_config).resolve())
    profile_path = resolve_profile_path(args.profile, project_root)
    profile_conf = load_json(profile_path)

    problems = validate_config(global_conf, profile_conf, project_root)
    if problems:
        for p in problems:
            print(f"Config error: {p}", file=sys.stderr)
        return 2

    chromium_path, user_data_dir, extensions = resolve_launch_context(
        global_conf,
        profile_conf,
        profile_path,
        project_root,
    )

    runtime_config = build_runtime_config(global_conf, profile_conf, profile_path, user_data_dir)
    runtime_config_path = write_runtime_config(user_data_dir, runtime_config)
    cmd = build_launch_command(
        chromium_path,
        user_data_dir,
        extensions,
        global_conf,
        profile_conf,
        runtime_config_path,
    )

    print(f"Profile: {profile_path}")
    print(f"User data dir: {user_data_dir}")
    print(f"Runtime config: {runtime_config_path}")
    print(f"Shared extensions loaded: {len(extensions)}")
    print("Command:")
    print("  " + " ".join(shlex.quote(c) for c in cmd))

    if args.dry_run:
        return 0

    proc = subprocess.run(cmd, check=False)
    return proc.returncode


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="antidetect",
        description="Launch isolated Chromium profiles with shared extension set.",
    )
    parser.add_argument(
        "--global-config",
        default="configs/global.json",
        help="Path to global config JSON (default: configs/global.json)",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    launch = subparsers.add_parser("launch", help="Launch a profile")
    launch.add_argument("--profile", required=True, help="Profile name or JSON file path")
    launch.add_argument("--dry-run", action="store_true", help="Print command only")

    validate = subparsers.add_parser("validate", help="Validate configs")
    validate.add_argument("--profile", required=True, help="Profile name or JSON file path")

    subparsers.add_parser("list-extensions", help="List shared extensions")
    return parser


def main() -> int:
    parser = make_parser()
    args = parser.parse_args()
    project_root = Path(__file__).resolve().parents[1]

    if args.command == "validate":
        return command_validate(args, project_root)
    if args.command == "list-extensions":
        return command_list_extensions(args, project_root)
    if args.command == "launch":
        return command_launch(args, project_root)
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
