#!/usr/bin/env python3
"""Update registry.json — single source of truth for all vhackpad.com sites."""

import json
import sys
import fcntl
import os
from datetime import datetime, timezone

REGISTRY = "/opt/vhack-deploy/registry.json"


def load_registry():
    try:
        with open(REGISTRY) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"sites": {}}


def save_registry(reg):
    tmp = REGISTRY + ".tmp"
    with open(tmp, "w") as f:
        json.dump(reg, f, indent=2, sort_keys=True)
        f.write("\n")
    os.rename(tmp, REGISTRY)


def cmd_add(args):
    site = args[0]
    site_type = args[1] if len(args) > 1 else "static"
    port = args[2] if len(args) > 2 and args[2] else None

    reg = load_registry()
    entry = {
        "type": site_type,
        "created": datetime.now(timezone.utc).isoformat(),
        "release_count": 0,
        "current_release": None,
    }
    if port:
        entry["port"] = int(port)

    reg["sites"][site] = entry
    save_registry(reg)
    print(f"Added {site} to registry")


def cmd_remove(args):
    site = args[0]
    reg = load_registry()
    if site in reg["sites"]:
        del reg["sites"][site]
        save_registry(reg)
        print(f"Removed {site} from registry")
    else:
        print(f"Site {site} not in registry", file=sys.stderr)


def cmd_update(args):
    site = args[0]
    reg = load_registry()
    if site not in reg["sites"]:
        print(f"Site {site} not in registry", file=sys.stderr)
        sys.exit(1)

    # Parse key-value pairs
    pairs = args[1:]
    for i in range(0, len(pairs), 2):
        key = pairs[i]
        value = pairs[i + 1]
        # Auto-convert numeric strings
        try:
            value = int(value)
        except ValueError:
            pass
        reg["sites"][site][key] = value

    reg["sites"][site]["last_deploy"] = datetime.now(timezone.utc).isoformat()
    save_registry(reg)
    print(f"Updated {site} in registry")


def main():
    if len(sys.argv) < 3:
        print("Usage: update-registry.py <add|remove|update> <site> [args...]", file=sys.stderr)
        sys.exit(1)

    action = sys.argv[1]
    args = sys.argv[2:]

    # File locking to prevent concurrent updates
    lock_path = REGISTRY + ".lock"
    lock_fd = open(lock_path, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)

        if action == "add":
            cmd_add(args)
        elif action == "remove":
            cmd_remove(args)
        elif action == "update":
            cmd_update(args)
        else:
            print(f"Unknown action: {action}", file=sys.stderr)
            sys.exit(1)
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()


if __name__ == "__main__":
    main()
