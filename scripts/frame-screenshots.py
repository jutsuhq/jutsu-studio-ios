# Builds the App Store screenshots: results first (a full-bleed take, three takes side by side), then the app's
# screens framed with a headline. One set per size, iPhone 6.9" (1320x2868) and iPad 13" (2064x2752).
# Usage: python3 scripts/frame-screenshots.py <art folder> <iPhone shots> <iPad shots> <output folder>
# art: hero.jpg, t1-t3.jpg (frames of takes), i1-i4.png (generated images).
# Shots come from a Debug build with -debug.sampleAccount YES -library.sampleHistory YES -debug.sampleQueue YES,
# named 1-create.png, 3-library.png, 5-queue.png.
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
FONT = os.path.join(ROOT, "App", "Resources", "Fonts", "BarlowCondensed-ExtraBold.ttf")
SUB = "/System/Library/Fonts/HelveticaNeue.ttc"
LIME = (212, 255, 42)
VIOLET = (139, 92, 246)
PINK = (244, 114, 182)
INK = (8, 8, 12)
BADGE = "UNOFFICIAL HIGGSFIELD CLIENT"


def cover(im, w, h, focus=0.5):
    """Scales and crops to fill w x h; focus is where the crop sits vertically (0 top, 1 bottom)."""
    scale = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.LANCZOS)
    x = (im.width - w) // 2
    y = round((im.height - h) * focus)
    return im.crop((x, y, x + w, y + h))


def shade(canvas, top, bottom):
    """Darkens the top `top` and bottom `bottom` fractions so text reads over a photo."""
    w, h = canvas.size
    mask = Image.new("L", (1, h))
    for y in range(h):
        t = 0
        if y < h * top:
            t = 1 - y / (h * top)
        elif y > h * (1 - bottom):
            t = (y - h * (1 - bottom)) / (h * bottom)
        mask.putpixel((0, y), int(235 * min(1, t) ** 1.2))
    return Image.composite(Image.new("RGB", (w, h), INK), canvas, mask.resize((w, h)))


def glow(w, h):
    base = Image.new("RGB", (w, h), INK)
    for cx, cy, r, col in [(0.15, 0.12, 0.55, VIOLET), (0.9, 0.35, 0.5, PINK), (0.5, 1.0, 0.6, (60, 40, 140))]:
        m = Image.new("L", (w, h), 0)
        rr = int(w * r)
        ImageDraw.Draw(m).ellipse([w * cx - rr, h * cy - rr, w * cx + rr, h * cy + rr], fill=150)
        base = Image.composite(Image.new("RGB", (w, h), col), base, m.filter(ImageFilter.GaussianBlur(rr * 0.6)))
    return Image.blend(Image.new("RGB", (w, h), INK), base, 0.55)


def headline(canvas, lines, sub, top=None):
    """Two lines, white then lime, and a grey line under them; returns the y below the text."""
    w, h = canvas.size
    d = ImageDraw.Draw(canvas)
    size = int(w * (0.075 if w > 1600 else 0.12))
    font = ImageFont.truetype(FONT, size)
    while max(d.textlength(t, font=font) for t in lines) > w * 0.9:
        font = ImageFont.truetype(FONT, font.size - 4)
    y = int(h * 0.055) if top is None else top
    for i, (text, color) in enumerate(zip(lines, [(255, 255, 255), LIME])):
        d.text(((w - d.textlength(text, font=font)) / 2, y + i * font.size * 0.95), text, font=font, fill=color)
    y += 2 * font.size * 0.95 + font.size * 0.2
    small = ImageFont.truetype(SUB, int(font.size * 0.36))
    while d.textlength(sub, font=small) > w * 0.9:
        small = ImageFont.truetype(SUB, small.size - 2)
    d.text(((w - d.textlength(sub, font=small)) / 2, y), sub, font=small, fill=(215, 215, 225))
    return int(y + small.size * 1.6)


def badge(canvas, text, y):
    """A lime outlined pill centred at y."""
    w, _ = canvas.size
    d = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(SUB, int(w * (0.016 if w > 1600 else 0.026)))
    tw = d.textlength(text, font=font)
    px, py = font.size * 1.2, font.size * 0.7
    box = [(w - tw) / 2 - px, y - py, (w + tw) / 2 + px, y + font.size + py]
    d.rounded_rectangle(box, radius=(box[3] - box[1]) / 2, fill=(0, 0, 0), outline=LIME, width=max(2, w // 400))
    d.text(((w - tw) / 2, y), text, font=font, fill=LIME)


def hero(art, w, h, lines, sub):
    canvas = shade(cover(Image.open(art).convert("RGB"), w, h, 0.0 if w > 1600 else 0.45), 0.34, 0.16)
    headline(canvas, lines, sub)
    badge(canvas, BADGE, int(h * 0.93))
    return canvas


def strips(arts, w, h, lines, sub):
    """Takes side by side under the headline, with thin gaps."""
    canvas = glow(w, h)
    y0 = headline(canvas, lines, sub) + int(h * 0.01)
    gap = max(8, w // 120)
    sw = (w - gap * (len(arts) + 1)) // len(arts)
    for i, art in enumerate(arts):
        tile = cover(Image.open(art).convert("RGB"), sw, h - y0 - gap, 0.3)
        mask = Image.new("L", tile.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile.width - 1, tile.height - 1], sw // 10, fill=255)
        canvas.paste(tile, (gap + i * (sw + gap), y0), mask)
    return canvas


def grid(arts, w, h, lines, sub):
    """Generated images in a 2 x 2 grid under the headline."""
    canvas = glow(w, h)
    y0 = headline(canvas, lines, sub) + int(h * 0.01)
    gap = max(8, w // 90)
    cw = (w - gap * 3) // 2
    ch = (h - y0 - gap * 2) // 2
    for i, art in enumerate(arts):
        tile = cover(Image.open(art).convert("RGB"), cw, ch, 0.25)
        mask = Image.new("L", tile.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, cw - 1, ch - 1], cw // 14, fill=255)
        canvas.paste(tile, (gap + (i % 2) * (cw + gap), y0 + (i // 2) * (ch + gap)), mask)
    return canvas


def screen(shot, w, h, lines, sub):
    """The app's screen with round corners under the headline, running off the bottom on iPhone."""
    canvas = glow(w, h)
    y0 = headline(canvas, lines, sub)
    im = Image.open(shot).convert("RGB")
    pad = w > 1600
    scale = (h - y0 - int(h * 0.03)) / h if pad else (h - y0 + int(h * 0.08)) / h * 0.98
    sw, sh = int(im.width * scale), int(im.height * scale)
    im = im.resize((sw, sh), Image.Resampling.LANCZOS)
    radius = int(sw * (0.03 if pad else 0.11))
    x0 = (w - sw) // 2
    shadow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x0 - 6, y0 + 20, x0 + sw + 6, y0 + sh + 40], radius, fill=180)
    canvas = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    border = max(4, int(w * 0.006))
    ImageDraw.Draw(canvas).rounded_rectangle(
        [x0 - border, y0 - border, x0 + sw + border, y0 + sh + border], radius + border, fill=(40, 40, 48))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius, fill=255)
    canvas.paste(im, (x0, y0), mask)
    return canvas


def build(art, shots, out, w, h):
    os.makedirs(out, exist_ok=True)
    a = lambda name: os.path.join(art, name)
    s = lambda name: os.path.join(shots, name)
    frames = [
        hero(a("hero.jpg"), w, h, ["TURN ANY CLIP", "INTO A NEW SCENE"], "Your video, a new character, the same moves"),
        strips([a("t1.jpg"), a("t2.jpg"), a("t3.jpg")], w, h, ["ANY CHARACTER", "ANY STYLE"],
               "Motion transfer, restyle and object swap"),
        screen(s("3-library.png"), w, h, ["EVERY TAKE", "IN ONE PLACE"], "Your Higgsfield history, always with you"),
        screen(s("1-create.png"), w, h, ["SEE THE PRICE", "BEFORE YOU GENERATE"], "Every video model and its options"),
        grid([a("i1.png"), a("i2.png"), a("i3.png"), a("i4.png")], w, h, ["IMAGES", "UP TO 4K"],
             "Pick a shape, a size and how many"),
        screen(s("5-queue.png"), w, h, ["SEND IT", "AND WALK AWAY"], "The queue keeps going in the background"),
    ]
    for i, frame in enumerate(frames, 1):
        frame.save(os.path.join(out, f"{i}.png"))


if __name__ == "__main__":
    art, phone, pad, out = sys.argv[1:5]
    build(art, phone, os.path.join(out, "iphone"), 1320, 2868)
    build(art, pad, os.path.join(out, "ipad"), 2064, 2752)
