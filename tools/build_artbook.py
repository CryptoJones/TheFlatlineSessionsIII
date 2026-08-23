#!/usr/bin/env python3
"""Build docs/The_Art_of_The_Flatline_Sessions_III.pdf from the live plate set.

The art book is 1 title page + 144 plate spreads (image page, then prompt page),
289 pages at 960x540pt. Plate metadata comes from docs/art-review-index.md, which
is the source of truth for plate number, type, source asset, and render prompt.

This tool exists because the original generator lived only in a scratch directory
on one machine. Run it after any change to the plates in assets/.

    python3 tools/build_artbook.py

Requires: reportlab, Pillow.
"""
import io
import re
import sys
from pathlib import Path

from PIL import Image
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "docs/art-review-index.md"
COVER = ROOT / "docs/album_art/the_flatline_sessions_iii_mona_lisa_underdrive.png"
OUT = ROOT / "docs/The_Art_of_The_Flatline_Sessions_III.pdf"

# --- design tokens, matched to the v1.2.5 book -------------------------------
# Geometry is expressed top-down (as the book was laid out) and flipped by `y()`.
PAGE_W, PAGE_H = 960.0, 540.0
BG = (0x0C / 255, 0x0E / 255, 0x13 / 255)
TEAL = (0x37 / 255, 0xD2 / 255, 0xC3 / 255)
LIGHT = (0xE8 / 255, 0xE9 / 255, 0xEE / 255)
MUTED = (0x9A / 255, 0xA0 / 255, 0xAD / 255)

TITLE = "The Art of The Flatline Sessions III"
SUB_A = "Mona Lisa Overdrive"
SUB_SEP = "I"  # ZapfDingbats separator glyph
SUB_B = "A fan-made 2026 cyberpunk remaster · background-plate art book"

COVER_BOX = (210.0, 0.0, 540.0, 540.0)    # x, top, w, h
PLATE_BOX = (60.0, 30.0, 840.0, 480.0)
SCRIM_BOX = (0.0, 402.0, 960.0, 138.0)
ACCENT_BOX = (0.0, 0.0, 8.0, 540.0)

TEXT_X = 48.0
PROMPT_WRAP_W = 872.0
PROMPT_LEADING = 13.2
PROMPT_MAX_LINES = 2
JPEG_QUALITY = 85

ROW_RE = re.compile(r"^\|\s*(P\d+)\s*\|([^|]*)\|\s*`([^`]+)`\s*\|(.*?)\s*\|\s*$")


def y(top):
    """Convert a top-down y coordinate to reportlab's bottom-up space."""
    return PAGE_H - top


def load_index():
    """Return [(plate, type, asset_path, prompt)] in plate order."""
    rows = []
    for line in INDEX.read_text(encoding="utf-8").splitlines():
        m = ROW_RE.match(line)
        if m:
            rows.append((m.group(1), m.group(2).strip(), m.group(3).strip(), m.group(4).strip()))
    rows.sort(key=lambda r: int(r[0][1:]))
    return rows


def as_jpeg(path, quality=JPEG_QUALITY):
    """Re-encode a plate as JPEG so the book stays ~30MB rather than ~300MB."""
    with Image.open(path) as im:
        buf = io.BytesIO()
        im.convert("RGB").save(buf, "JPEG", quality=quality, optimize=True, progressive=False)
    buf.seek(0)
    return ImageReader(buf)


def wrap(text, font, size, width, max_lines=PROMPT_MAX_LINES):
    """Greedy wrap to `width`, hard-capped at `max_lines`."""
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if pdfmetrics.stringWidth(trial, font, size) <= width:
            cur = trial
        else:
            lines.append(cur)
            cur = word
            if len(lines) == max_lines:
                break
    if cur and len(lines) < max_lines:
        lines.append(cur)
    return lines[:max_lines]


def fill_box(c, box, color):
    x, top, w, h = box
    c.setFillColorRGB(*color)
    c.rect(x, y(top + h), w, h, stroke=0, fill=1)


def rule(c, x0, x1, top, color=TEAL, width=1.0):
    c.setStrokeColorRGB(*color)
    c.setLineWidth(width)
    c.line(x0, y(top), x1, y(top))


def text_at(c, x, top, s, font, size, color):
    c.setFont(font, size)
    c.setFillColorRGB(*color)
    c.drawString(x, y(top), s)


def paint_bg(c):
    fill_box(c, (0.0, 0.0, PAGE_W, PAGE_H), BG)


def build_title(c):
    paint_bg(c)
    cx, ctop, cw, ch = COVER_BOX
    c.drawImage(as_jpeg(COVER), cx, y(ctop + ch), cw, ch)
    fill_box(c, SCRIM_BOX, BG)          # scrim so the title sits on flat ground
    rule(c, 360, 600, 470)
    text_at(c, (PAGE_W - pdfmetrics.stringWidth(TITLE, "Helvetica-Bold", 33)) / 2, 456,
            TITLE, "Helvetica-Bold", 33, LIGHT)
    # subtitle is three runs on one baseline, centered as a unit
    wa = pdfmetrics.stringWidth(SUB_A, "Helvetica-Oblique", 20)
    ws = pdfmetrics.stringWidth(SUB_SEP, "ZapfDingbats", 20)
    wb = pdfmetrics.stringWidth(SUB_B, "Helvetica-Oblique", 20)
    x = (PAGE_W - (wa + ws + wb)) / 2
    text_at(c, x, 496, SUB_A, "Helvetica-Oblique", 20, TEAL)
    text_at(c, x + wa, 496, SUB_SEP, "ZapfDingbats", 20, TEAL)
    text_at(c, x + wa + ws, 496, SUB_B, "Helvetica-Oblique", 20, TEAL)
    c.showPage()


def build_image_page(c, asset):
    paint_bg(c)
    px, ptop, pw, ph = PLATE_BOX
    c.drawImage(as_jpeg(asset), px, y(ptop + ph), pw, ph)
    c.showPage()


def build_prompt_page(c, plate, kind, prompt):
    paint_bg(c)
    fill_box(c, ACCENT_BOX, TEAL)
    text_at(c, TEXT_X, 74, f"Plate {plate}", "Helvetica-Bold", 34, LIGHT)
    rule(c, 50, 300, 88)
    text_at(c, TEXT_X, 97, "Type", "Helvetica-Bold", 11, TEAL)
    text_at(c, TEXT_X, 113.5, kind, "Helvetica", 11.5, LIGHT)
    text_at(c, TEXT_X, 136.5, "Render prompt", "Helvetica-Bold", 11, TEAL)
    top = 151.1
    for line in wrap(prompt, "Helvetica", 9.6, PROMPT_WRAP_W):
        text_at(c, TEXT_X, top, line, "Helvetica", 9.6, MUTED)
        top += PROMPT_LEADING
    c.showPage()


def main():
    rows = load_index()
    if len(rows) != 144:
        sys.exit(f"expected 144 plates in the index, parsed {len(rows)}")

    missing = [a for _, _, a, _ in rows if not (ROOT / a).exists()]
    if missing:
        sys.exit("missing plate assets:\n  " + "\n  ".join(missing))

    c = canvas.Canvas(str(OUT), pagesize=(PAGE_W, PAGE_H), pageCompression=1)
    c.setTitle("The Art of The Flatline Sessions III")
    build_title(c)
    for plate, kind, asset, prompt in rows:
        build_image_page(c, ROOT / asset)
        build_prompt_page(c, plate, kind, prompt)
    c.save()
    print(f"wrote {OUT.relative_to(ROOT)} — {1 + 2 * len(rows)} pages, "
          f"{OUT.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
