#!/usr/bin/env python3
import json
import os
import struct

def get_cursor_sizes(theme_path):
    cursors_dir = os.path.join(theme_path, "cursors")
    if not os.path.isdir(cursors_dir):
        return []
    candidates = ["left_ptr", "default", "arrow"]
    cursor_file = None
    for c in candidates:
        p = os.path.join(cursors_dir, c)
        if os.path.isfile(p):
            cursor_file = p
            break
    if not cursor_file:
        try:
            entries = os.listdir(cursors_dir)
            for e in entries:
                p = os.path.join(cursors_dir, e)
                if os.path.isfile(p):
                    cursor_file = p
                    break
        except OSError:
            pass
    if not cursor_file:
        return []
    try:
        with open(cursor_file, "rb") as f:
            data = f.read(16)
            if len(data) < 16 or data[:4] != b"Xcur":
                return []
            _, _, _, ntoc = struct.unpack("=4sIII", data)
            sizes = set()
            for _ in range(ntoc):
                toc = f.read(12)
                if len(toc) < 12:
                    break
                type_, subtype, _ = struct.unpack("=III", toc)
                if type_ == 0xfffd0002 and subtype > 0:
                    sizes.add(subtype)
            return sorted(list(sizes))
    except Exception:
        return []

def get_cursor_themes():
    search_dirs = [
        os.path.expanduser("~/.icons"),
        os.path.expanduser("~/.local/share/icons"),
        "/usr/local/share/icons",
        "/usr/share/icons",
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
            if not os.path.isdir(theme_path):
                continue
            if item.lower() in ("default", "hicolor", "locolor"):
                continue

            has_cursors = os.path.isdir(os.path.join(theme_path, "cursors"))
            has_hyprcursor = os.path.isfile(os.path.join(theme_path, "manifest.hl"))
            
            if not (has_cursors or has_hyprcursor):
                continue

            display_name = item
            comment = ""
            index_file = os.path.join(theme_path, "index.theme")
            if os.path.isfile(index_file):
                try:
                    with open(index_file, "r", encoding="utf-8", errors="ignore") as f:
                        for line in f:
                            stripped = line.strip()
                            if stripped.startswith("Name="):
                                val = stripped.split("Name=", 1)[1].strip()
                                if val:
                                    display_name = val
                            elif stripped.startswith("Comment="):
                                comment = stripped.split("Comment=", 1)[1].strip()
                except Exception:
                    pass

            sizes = get_cursor_sizes(theme_path)

            if item not in themes:
                themes[item] = {
                    "id": item,
                    "name": display_name,
                    "comment": comment,
                    "hyprcursor": has_hyprcursor,
                    "sizes": sizes,
                    "min_size": min(sizes) if sizes else 24,
                    "path": theme_path
                }

    sorted_themes = sorted(themes.values(), key=lambda x: x["name"].lower())
    return sorted_themes

if __name__ == "__main__":
    result = get_cursor_themes()
    print(json.dumps(result, indent=2))

