"""Trim empty terminal background below the last line of text in a screenshot (in place)."""
import sys
from PIL import Image

path = sys.argv[1]
im = Image.open(path).convert("RGB")
w, h = im.size
bg = im.getpixel((w // 2, h - 40))          # terminal background colour near the bottom
px = im.load()
last = 0
for y in range(h - 25, 0, -1):
    row_has_text = any(
        sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 60 for x in range(40, w - 40, 3)
    )
    if row_has_text:
        last = y
        break
cut = min(h, last + 60)
if cut < h - 20:
    im.crop((0, 0, w, cut)).save(path)
