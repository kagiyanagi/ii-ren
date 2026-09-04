#!/usr/bin/env python3
import json
import os

def get_icon_themes():
    search_dirs = [
        "/usr/share/icons",
        os.path.expanduser("~/.local/share/icons"),
        os.path.expanduser("~/.icons")
    ]
    
    themes = {}
    
    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        try:
            entries = os.listdir(d)
        except OSError:
            continue

        for item in entries:
            theme_path = os.path.join(d, item)
            index_file = os.path.join(theme_path, "index.theme")
            if not (os.path.isdir(theme_path) and os.path.isfile(index_file)):
                continue

            # Ignore pure cursor themes
            is_cursor_only = os.path.isdir(os.path.join(theme_path, "cursors")) and not any(
                os.path.isdir(os.path.join(theme_path, sub))
                for sub in ("apps", "places", "64x64", "48x48", "32x32", "scalable", "mimetypes")
            )
            if is_cursor_only:
                continue

            if item.lower() in ("default", "hicolor", "locolor") or item.endswith("-Dynamic"):
                continue

            display_name = item
            is_dynamic = False
            inherits = ""
            
            try:
                with open(index_file, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        line_stripped = line.strip()
                        if line_stripped.startswith("Name="):
                            display_name = line_stripped.split("Name=", 1)[1].strip()
                        elif line_stripped == "FollowsColorScheme=true":
                            is_dynamic = True
                        elif line_stripped.startswith("Inherits="):
                            inherits = line_stripped.split("Inherits=", 1)[1].strip()
            except Exception:
                pass

            # Filter out themes like Papirus that declare FollowsColorScheme but don't natively tint folders
            # Only known true dynamic folder themes (like Breeze variants) will stay dynamic
            item_lower = item.lower()
            if "papirus" in item_lower or "ryoku" in item_lower:
                is_dynamic = False
            
            # Explicitly ensure breeze family is marked dynamic (since breeze-plus inherits it)
            if "breeze" in item_lower:
                is_dynamic = True

            if item not in themes:
                themes[item] = {
                    "id": item,
                    "name": display_name,
                    "dynamic": is_dynamic,
                    "inherits": inherits,
                    "path": theme_path
                }

    # Sort themes: dynamic first, then alphabetical by name
    sorted_themes = sorted(
        themes.values(),
        key=lambda x: (not x["dynamic"], x["name"].lower())
    )
    return sorted_themes

if __name__ == "__main__":
    result = get_icon_themes()
    print(json.dumps(result, indent=2))
