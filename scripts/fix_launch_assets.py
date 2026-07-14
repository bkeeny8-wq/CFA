#!/usr/bin/env python3
"""fix_launch_assets.py - resize LaunchLogo to proper 2x/3x point sizes."""
import json, os
from PIL import Image

D = "CFAL3/Assets.xcassets/LaunchLogo.imageset"
src = Image.open(os.path.join(D, "LaunchLogo.png")).convert("RGBA")

# 160-pt logo: 320 px @2x, 480 px @3x
src.resize((320, 320), Image.LANCZOS).save(os.path.join(D, "LaunchLogo@2x.png"))
src.resize((480, 480), Image.LANCZOS).save(os.path.join(D, "LaunchLogo@3x.png"))
os.remove(os.path.join(D, "LaunchLogo.png"))

contents = {
  "images": [
    {"idiom": "universal", "scale": "1x"},
    {"filename": "LaunchLogo@2x.png", "idiom": "universal", "scale": "2x"},
    {"filename": "LaunchLogo@3x.png", "idiom": "universal", "scale": "3x"}
  ],
  "info": {"author": "xcode", "version": 1}
}
json.dump(contents, open(os.path.join(D, "Contents.json"), "w"), indent=2)
print("launch logo: 160pt (@2x 320px, @3x 480px) OK")

A = "CFAL3/Assets.xcassets/AppIcon.appiconset"
icon = Image.open(os.path.join(A, "AppIcon-1024.png")).convert("RGB")
bg = icon.getpixel((4, 4))                     # corner background color
canvas = Image.new("RGB", (1024, 1024), bg)
scaled = icon.resize((737, 737), Image.LANCZOS)  # 72% of 1024
canvas.paste(scaled, ((1024 - 737) // 2, (1024 - 737) // 2))
canvas.save(os.path.join(A, "AppIcon-1024.png"))
print("app icon: artwork rescaled to 72% with background fill OK")
