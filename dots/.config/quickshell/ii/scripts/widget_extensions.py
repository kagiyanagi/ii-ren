#!/usr/bin/env python3
"""
widget_extensions.py — Backend helper script for WidgetExtensionManager.
Supports:
  - discover [limit]: Query GitHub for community desktop widget repositories
  - install <url_or_path> <dest_parent_dir>: Clone or link widget extension
  - backup <ext_id> <source_path> <backup_parent_dir>: Backup widget before updates
"""

import sys
import os
import json
import shutil
import subprocess
import urllib.request
import urllib.error
from datetime import datetime


def discover(limit_str="30"):
    try:
        limit = max(1, min(100, int(limit_str)))
    except ValueError:
        limit = 30

    query = '"ii-vynx-extension"+OR+"ii-ren-extension"+OR+"quickshell-widget"+in:topic'
    url = f"https://api.github.com/search/repositories?q={query}&sort=stars&order=desc&per_page={limit}"

    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "ii-ren-shell/1.0"
        }
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(json.dumps({"status": "error", "error": f"GitHub API error: {e.code} {e.reason}"}))
        return
    except urllib.error.URLError as e:
        print(json.dumps({"status": "error", "error": f"Network error: {e.reason}"}))
        return
    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}))
        return

    items = data.get("items", [])
    results = []
    seen = set()

    for item in items:
        full_name = item.get("full_name", "")
        if full_name in seen:
            continue
        seen.add(full_name)

        owner = item.get("owner", {})
        results.append({
            "name": item.get("name", ""),
            "fullName": full_name,
            "description": item.get("description") or "",
            "stars": item.get("stargazers_count", 0),
            "author": owner.get("login", ""),
            "avatarUrl": owner.get("avatar_url", ""),
            "repoUrl": item.get("html_url", ""),
            "cloneUrl": item.get("clone_url", ""),
            "updatedAt": item.get("updated_at", "")
        })

    print(json.dumps({"status": "ok", "results": results}))


def install(url_or_path, dest_parent_dir):
    if not url_or_path:
        print(json.dumps({"status": "error", "error": "No URL or path provided"}))
        return

    # Check if local path
    clean_path = url_or_path.replace("file://", "").strip()
    if clean_path.startswith("/") or os.path.exists(clean_path):
        abs_path = os.path.abspath(clean_path)
        if not os.path.isdir(abs_path):
            print(json.dumps({"status": "error", "error": f"Local path is not a directory: {abs_path}"}))
            return

        widget_json = os.path.join(abs_path, "widget.json")
        ext_json = os.path.join(abs_path, "extension.json")
        if not os.path.exists(widget_json) and not os.path.exists(ext_json):
            print(json.dumps({"status": "error", "error": f"widget.json or extension.json not found in {abs_path}"}))
            return

        ext_id = os.path.basename(abs_path).replace(" ", "-")
        print(json.dumps({
            "status": "ok",
            "extId": ext_id,
            "installedPath": abs_path,
            "isLocal": True
        }))
        return

    # Remote git URL
    ext_id = url_or_path.rstrip("/").split("/")[-1].replace(".git", "").replace(" ", "-")
    os.makedirs(dest_parent_dir, exist_ok=True)
    dest_path = os.path.join(dest_parent_dir, ext_id)

    if os.path.exists(dest_path):
        shutil.rmtree(dest_path, ignore_errors=True)

    try:
        proc = subprocess.run(
            ["git", "clone", "--depth", "1", url_or_path, dest_path],
            capture_output=True,
            text=True,
            timeout=60,
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(json.dumps({"status": "error", "error": f"git clone failed: {e.stderr.strip()}"}))
        return
    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}))
        return

    widget_json = os.path.join(dest_path, "widget.json")
    ext_json = os.path.join(dest_path, "extension.json")
    if not os.path.exists(widget_json) and not os.path.exists(ext_json):
        print(json.dumps({"status": "error", "error": "Repository does not contain widget.json or extension.json"}))
        return

    print(json.dumps({
        "status": "ok",
        "extId": ext_id,
        "installedPath": dest_path,
        "isLocal": False
    }))


def backup(ext_id, source_path, backup_parent_dir):
    if not os.path.exists(source_path):
        print(json.dumps({"status": "error", "error": f"Source path does not exist: {source_path}"}))
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    os.makedirs(backup_parent_dir, exist_ok=True)
    backup_path = os.path.join(backup_parent_dir, f"{ext_id}_{timestamp}")

    try:
        shutil.copytree(source_path, backup_path)
        print(json.dumps({"status": "ok", "backupPath": backup_path}))
    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}))


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "error": "No command specified"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "discover":
        limit = sys.argv[2] if len(sys.argv) > 2 else "30"
        discover(limit)
    elif cmd == "install":
        if len(sys.argv) < 4:
            print(json.dumps({"status": "error", "error": "Usage: install <urlOrPath> <destParentDir>"}))
            sys.exit(1)
        install(sys.argv[2], sys.argv[3])
    elif cmd == "backup":
        if len(sys.argv) < 5:
            print(json.dumps({"status": "error", "error": "Usage: backup <extId> <sourcePath> <backupParentDir>"}))
            sys.exit(1)
        backup(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(json.dumps({"status": "error", "error": f"Unknown command: {cmd}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
