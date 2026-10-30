#!/usr/bin/env python3
"""Render Throughline's simple vector-style macOS icon from geometric shapes.

Requires Pillow only when regenerating the art; the app ships the generated PNG/iconset/icns.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import subprocess

ROOT = Path(__file__).resolve().parent
SCALE = 4
SIZE = 1024

def q(value):
    return round(value * SCALE)

image = Image.new('RGBA', (q(SIZE), q(SIZE)), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)

def rounded(box, radius, color):
    draw.rounded_rectangle(tuple(q(v) for v in box), radius=q(radius), fill=color)

# Matte graphite housing, warm ivory monogram, one continuous copper study line.
rounded((64, 64, 960, 960), 205, '#242622')
rounded((75, 75, 949, 949), 195, '#292b28')
rounded((268, 289, 756, 383), 47, '#f7f4ec')
rounded((465, 333, 559, 746), 47, '#f7f4ec')
rounded((276, 529, 748, 550), 10, '#b56e35')

master = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
master.save(ROOT / 'AppIcon-1024.png', optimize=True)
iconset = ROOT / 'AppIcon.iconset'
iconset.mkdir(exist_ok=True)
for points in (16, 32, 128, 256, 512):
    for multiplier, suffix in ((1, ''), (2, '@2x')):
        pixels = points * multiplier
        destination = iconset / f'icon_{points}x{points}{suffix}.png'
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(destination, optimize=True)
subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(iconset), '-o', str(ROOT / 'AppIcon.icns')], check=True)
