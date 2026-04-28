#!/usr/bin/env python3
"""Generates the iOS App Icon set for Expense Tracker.

Renders a single 1024x1024 master PNG (App Store / Marketing icon — iOS 14+
auto-derives smaller sizes from this) and writes Contents.json next to it.
The design: a rounded-square purple gradient with a stylised ₹ glyph and a
small spark, echoing the in-app Theme.accentPrimary palette.
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import json
import os
import math

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "ios", "ExpenseTracker", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_gradient(img, top, bottom):
    """Vertical gradient fill across the entire image."""
    px = img.load()
    w, h = img.size
    for y in range(h):
        t = y / (h - 1)
        c = lerp(top, bottom, t) + (255,)
        for x in range(w):
            px[x, y] = c


def draw_radial_glow(img, cx, cy, radius, color, alpha):
    """Soft radial glow centered at (cx, cy)."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color + (alpha,))
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=radius * 0.4))
    img.alpha_composite(overlay)


def draw_rounded_card(img, padding, radius, fill_top, fill_bottom):
    """Inner rounded card with its own gradient; gives the icon depth."""
    w, h = img.size
    card = Image.new("RGBA", img.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle(
        [padding, padding, w - padding, h - padding],
        radius=radius,
        fill=(0, 0, 0, 255),
    )
    grad = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gpx = grad.load()
    for y in range(h):
        t = y / (h - 1)
        c = lerp(fill_top, fill_bottom, t) + (255,)
        for x in range(w):
            gpx[x, y] = c
    grad.putalpha(card.split()[-1])
    img.alpha_composite(grad)


def draw_diagonal_sheen(img, padding, radius, alpha=70):
    """Subtle diagonal highlight on the card for that polished look."""
    w, h = img.size
    sheen = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.rounded_rectangle(
        [padding, padding, w - padding, h - padding],
        radius=radius,
        fill=(255, 255, 255, 0),
    )
    poly_alpha = Image.new("L", img.size, 0)
    pd = ImageDraw.Draw(poly_alpha)
    pd.polygon(
        [
            (padding - 20, padding - 20),
            (w * 0.55, padding - 20),
            (padding - 20, h * 0.55),
        ],
        fill=alpha,
    )
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(
        [padding, padding, w - padding, h - padding],
        radius=radius,
        fill=255,
    )
    poly_alpha = Image.composite(poly_alpha, Image.new("L", img.size, 0), mask)
    sheen.putalpha(poly_alpha)
    sheen_white = Image.new("RGBA", img.size, (255, 255, 255, 0))
    sheen_white.putalpha(poly_alpha)
    img.alpha_composite(sheen_white)


def find_font(size):
    """Find a bold-ish font that supports the rupee glyph."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            return ImageFont.truetype(p, size=size)
    return ImageFont.load_default()


def draw_rupee(img, cx, cy, target_size, color=(255, 255, 255, 255)):
    """Render the ₹ Unicode glyph from a bundled bold font, centered on (cx, cy).
    target_size is the desired pixel height of the glyph."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ]
    font = None
    for p in candidates:
        if os.path.exists(p):
            font = ImageFont.truetype(p, size=int(target_size * 1.25))
            break
    if font is None:
        return

    glyph = "₹"
    # Render once large to a transparent canvas, then compute the tight bbox
    # and stamp the centered crop onto the icon. This keeps the symbol visually
    # centered regardless of the font's internal padding.
    tmp = Image.new("RGBA", (int(target_size * 2), int(target_size * 2)), (0, 0, 0, 0))
    td = ImageDraw.Draw(tmp)
    td.text((target_size * 0.5, target_size * 0.3), glyph, font=font, fill=color)
    bbox = tmp.getbbox()
    if not bbox:
        return
    cropped = tmp.crop(bbox)
    # Optional drop-shadow for depth
    shadow = Image.new("RGBA", cropped.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.bitmap((0, 0), cropped.split()[-1], fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=target_size * 0.04))

    paste_x = int(cx - cropped.size[0] / 2)
    paste_y = int(cy - cropped.size[1] / 2)
    img.alpha_composite(shadow, dest=(paste_x + int(target_size * 0.025), paste_y + int(target_size * 0.04)))
    img.alpha_composite(cropped, dest=(paste_x, paste_y))


def draw_spark(img, cx, cy, length, color=(255, 211, 105, 255)):
    """Four-pointed spark — a tiny hint of value/energy in the upper-right."""
    d = ImageDraw.Draw(img)
    half = length / 2
    thick = max(int(length * 0.14), 3)
    # vertical
    d.rounded_rectangle(
        [cx - thick / 2, cy - half, cx + thick / 2, cy + half],
        radius=thick // 2,
        fill=color,
    )
    # horizontal
    d.rounded_rectangle(
        [cx - half, cy - thick / 2, cx + half, cy + thick / 2],
        radius=thick // 2,
        fill=color,
    )
    # soft glow
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = int(length * 0.9)
    gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=color[:3] + (90,))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=length * 0.35))
    img.alpha_composite(glow)


def draw_chart_bars(img, x, y, w, h, color=(255, 255, 255, 220)):
    """Three little ascending bars at the bottom — hints at "tracker"."""
    d = ImageDraw.Draw(img)
    gap = w * 0.18
    bar_w = (w - gap * 2) / 3
    heights = [h * 0.45, h * 0.75, h * 1.0]
    for i, bh in enumerate(heights):
        bx = x + i * (bar_w + gap)
        by = y + (h - bh)
        d.rounded_rectangle(
            [bx, by, bx + bar_w, y + h],
            radius=int(bar_w * 0.25),
            fill=color,
        )


def render_master(size=SIZE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Outer background (full bleed) — deep navy, matches Theme.bgPrimary
    bg = Image.new("RGBA", (size, size), (10, 10, 26, 255))
    img.alpha_composite(bg)

    # Inner rounded card with the brand purple gradient
    pad = int(size * 0.06)
    radius = int(size * 0.22)
    purple_top = (139, 92, 246)     # accentLight-ish
    purple_bottom = (76, 29, 149)   # deeper accent
    draw_rounded_card(img, pad, radius, purple_top, purple_bottom)

    # Soft glow behind the glyph
    draw_radial_glow(img, size // 2, int(size * 0.55), int(size * 0.45), (167, 139, 250), 110)

    # Diagonal sheen
    draw_diagonal_sheen(img, pad, radius, alpha=55)

    # ₹ glyph centered, slightly lower so the spark fits above
    glyph_size = int(size * 0.52)
    draw_rupee(img, size // 2, int(size * 0.48), glyph_size, color=(255, 255, 255, 255))

    # Tiny chart bars under the glyph
    bar_total_w = int(size * 0.22)
    bar_h = int(size * 0.07)
    bx = int((size - bar_total_w) / 2)
    by = int(size * 0.78)
    draw_chart_bars(img, bx, by, bar_total_w, bar_h, color=(255, 255, 255, 235))

    # Spark in upper right corner of the card
    sx = int(size * 0.76)
    sy = int(size * 0.22)
    draw_spark(img, sx, sy, int(size * 0.10), color=(253, 224, 71, 255))

    return img


def write_icon():
    img = render_master()

    # iOS 14+ accepts a single 1024x1024 marketing icon and slices the rest.
    # We also emit common @1x/@2x/@3x device variants so the asset catalogue
    # works on older Xcode versions and shows up correctly in older sims.
    variants = [
        ("Icon-1024.png", 1024),
        ("Icon-180.png", 180),
        ("Icon-167.png", 167),
        ("Icon-152.png", 152),
        ("Icon-120.png", 120),
        ("Icon-87.png", 87),
        ("Icon-80.png", 80),
        ("Icon-76.png", 76),
        ("Icon-60.png", 60),
        ("Icon-58.png", 58),
        ("Icon-40.png", 40),
        ("Icon-29.png", 29),
        ("Icon-20.png", 20),
    ]
    for name, sz in variants:
        if sz == 1024:
            out = img
        else:
            out = img.resize((sz, sz), Image.LANCZOS)
        out.save(os.path.join(OUT_DIR, name), "PNG", optimize=True)
        print(f"  wrote {name}")


def write_contents_json():
    contents = {
        "images": [
            {"size": "20x20", "idiom": "iphone", "filename": "Icon-40.png", "scale": "2x"},
            {"size": "20x20", "idiom": "iphone", "filename": "Icon-60.png", "scale": "3x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-58.png", "scale": "2x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-87.png", "scale": "3x"},
            {"size": "40x40", "idiom": "iphone", "filename": "Icon-80.png", "scale": "2x"},
            {"size": "40x40", "idiom": "iphone", "filename": "Icon-120.png", "scale": "3x"},
            {"size": "60x60", "idiom": "iphone", "filename": "Icon-120.png", "scale": "2x"},
            {"size": "60x60", "idiom": "iphone", "filename": "Icon-180.png", "scale": "3x"},
            {"size": "20x20", "idiom": "ipad", "filename": "Icon-20.png", "scale": "1x"},
            {"size": "20x20", "idiom": "ipad", "filename": "Icon-40.png", "scale": "2x"},
            {"size": "29x29", "idiom": "ipad", "filename": "Icon-29.png", "scale": "1x"},
            {"size": "29x29", "idiom": "ipad", "filename": "Icon-58.png", "scale": "2x"},
            {"size": "40x40", "idiom": "ipad", "filename": "Icon-40.png", "scale": "1x"},
            {"size": "40x40", "idiom": "ipad", "filename": "Icon-80.png", "scale": "2x"},
            {"size": "76x76", "idiom": "ipad", "filename": "Icon-76.png", "scale": "1x"},
            {"size": "76x76", "idiom": "ipad", "filename": "Icon-152.png", "scale": "2x"},
            {"size": "83.5x83.5", "idiom": "ipad", "filename": "Icon-167.png", "scale": "2x"},
            {"size": "1024x1024", "idiom": "ios-marketing", "filename": "Icon-1024.png", "scale": "1x"},
        ],
        "info": {"version": 1, "author": "xcode"},
    }
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("  wrote Contents.json")


if __name__ == "__main__":
    print(f"Generating icons in {OUT_DIR}")
    write_icon()
    write_contents_json()
    print("Done.")
