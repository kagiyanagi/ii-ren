#!/usr/bin/env python3
# Disclaimer: This script was ai-generated and went through minimal revision.
"""Background and text colour of each box on an image.

    text_color.py IMAGE X,Y,W,H [X,Y,W,H ...]

Prints a JSON list, one {"background", "text"} per box in order, and null for
a box with no pixels on the image. One run covers every box: the screen
translator has dozens, and a Python start with cv2 is ~200ms each.
"""

import cv2
import numpy as np
import json
import sys

def to_hex(color):
    return "#{:02x}{:02x}{:02x}".format(int(color[0]), int(color[1]), int(color[2]))

def get_colors(img_rgb):
    h, w, _ = img_rgb.shape

    # 1. Sample corner pixels (The background anchors)
    corners = np.array([
        img_rgb[0, 0],
        img_rgb[0, w-1],
        img_rgb[h-1, 0],
        img_rgb[h-1, w-1]
    ])

    # 2. Determine single dominant background
    # Using median handles noise/gradients better than a simple average
    bg_color = np.median(corners, axis=0).astype(int)

    # 3. Find the Text Color
    pixels = img_rgb.reshape(-1, 3).astype(int)
    distances = np.linalg.norm(pixels - bg_color, axis=1)

    # Take the 95th percentile of pixels furthest from background
    threshold = np.percentile(distances, 95)
    text_pixels = pixels[distances >= threshold]

    if len(text_pixels) == 0:
        text_color = [255, 255, 255] # Fallback
    else:
        text_color = np.median(text_pixels, axis=0).astype(int)

    return {
        "background": to_hex(bg_color),
        "text": to_hex(text_color)
    }

def crop(img, box):
    x, y, w, h = (int(float(v)) for v in box.split(","))
    part = img[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)]
    return part if part.size else None

if __name__ == "__main__":
    img = cv2.imread(sys.argv[1], cv2.IMREAD_COLOR)
    boxes = sys.argv[2:]
    if img is None:
        print(json.dumps([None] * len(boxes)))
        sys.exit(0)
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    parts = [crop(img_rgb, box) for box in boxes]
    print(json.dumps([None if p is None else get_colors(p) for p in parts]))
