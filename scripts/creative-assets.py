# Builds the App Store creative assets: the search-results video (3:2) and the product page header video (21:9).
# A phone shows the take being made in the app: the clip loaded, a reference added, the prompt typed, Generate
# tapped, the queue, then the new take. Beside it the clip itself turns into the new take: a lime line sweeps across,
# stops halfway to compare, then shows the new take whole. One take stands in for "your clip" and another take made
# from the same source is the result, both from the same frame so they stay in step.
# Usage: python3 scripts/creative-assets.py <output folder> <flow folder>
# flow: 0-source.png, 1-reference.png, 2-type.png, 3-type.png, 4-full.png, 5-queue.png (iPhone screenshots of
# Create from a Debug build with -debug.sourceVideo, -debug.reference and -debug.prompt). Takes come from Jutsu
# Studio's Library on this Mac; the icon is rendered from App/Resources/AppIcon.icon.
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
FONT = os.path.join(ROOT, "App", "Resources", "Fonts", "BarlowCondensed-ExtraBold.ttf")
SUB = "/System/Library/Fonts/HelveticaNeue.ttc"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
VIDEOS = os.path.expanduser("~/Library/Containers/com.jutsustudio.JutsuStudio/Data/Movies/Jutsu Studio/Videos/")
LIME = (212, 255, 42)
INK = (8, 8, 12)
SOURCE, RESULT = "bc55c943", "b22b88f1"  # the angel stands in for the clip, the fairy is the take made from it
# The fairy's camera sits a little further back; this zoom lines the two figures up.
RESULT_ZOOM = 1.1
LENGTH = 8
SLOW = 1  # the takes play at their own speed; both are 9 s, longer than the loop
# The phone's screens and how long each stays; the new take plays from the end of these to the end of the loop.
FLOW = [("0-source", 0.5), ("1-reference", 0.6), ("2-type", 0.35), ("3-type", 0.35), ("4-full", 0.6), ("5-queue", 0.5)]
TAP = (2.1, 2.4)  # Generate is tapped while the full prompt shows
DONE = sum(d for _, d in FLOW)
# Generate's centre on a 1320 x 2868 Create screenshot.
GENERATE = (1108, 2448)


def take(key):
    return VIDEOS + next(name for name in os.listdir(VIDEOS) if key in name and "4x" in name)


def glow(w, h):
    base = Image.new("RGB", (w, h), INK)
    for cx, cy, r, col in [(0.1, 0.1, 0.45, (139, 92, 246)), (0.55, 0.9, 0.4, (244, 114, 182))]:
        m = Image.new("L", (w, h), 0)
        rr = int(h * r * 1.6)
        ImageDraw.Draw(m).ellipse([w * cx - rr, h * cy - rr, w * cx + rr, h * cy + rr], fill=150)
        base = Image.composite(Image.new("RGB", (w, h), col), base, m.filter(ImageFilter.GaussianBlur(rr * 0.6)))
    return Image.blend(Image.new("RGB", (w, h), INK), base, 0.5)


def chip(text, fill, color, size):
    font = ImageFont.truetype(SUB, size)
    tw = int(ImageDraw.Draw(Image.new("RGBA", (1, 1))).textlength(text, font=font))
    w, h = tw + size * 2, int(size * 2.1)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, h - 1], h // 2, fill=fill)
    d.text((size, (h - size) / 2 - size * 0.08), text, font=font, fill=color)
    return im


def icon(size, folder):
    path = os.path.join(folder, "icon.png")
    if not os.path.exists(path):
        subprocess.run([ICTOOL, os.path.join(ROOT, "App", "Resources", "AppIcon.icon"), "--export-image",
                        "--output-file", path, "--platform", "iOS", "--rendition", "Default",
                        "--width", "512", "--height", "512", "--scale", "2"], check=True, capture_output=True)
    return Image.open(path).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def bezel(ph):
    return max(6, ph // 130)


def layout(safe, text_w, gap):
    """Text, phone and clip side by side filling the safe area (x, y, width, height), with even gaps."""
    x, y, sw, sh = safe
    b = bezel(sh)
    ph = sh - 2 * b
    pw = ph * 1320 // 2868
    px = x + text_w + gap + b
    vx = px + pw + b + gap
    return (x, y + sh // 2, text_w), (px, y + b, pw, ph), (vx, y, x + sw - vx, sh)


def background(w, h, text_box, phone, folder):
    """The glow, the headline in text_box (x, centre y, width), the icon line under it and the phone's bezel."""
    im = glow(w, h)
    d = ImageDraw.Draw(im)
    x, cy, tw = text_box
    font = ImageFont.truetype(FONT, int(h * 0.13))
    while max(d.textlength(t, font=font) for t in ["ONE CLIP.", "ANY CHARACTER."]) > tw:
        font = ImageFont.truetype(FONT, font.size - 4)
    y = cy - (font.size * 2.2 + int(font.size * 0.3) * 6.7) / 2
    for i, (t, c) in enumerate([("ONE CLIP.", (255, 255, 255)), ("ANY CHARACTER.", LIME)]):
        d.text((x, y + i * font.size * 0.95), t, font=font, fill=c)
    y += font.size * 2.2
    small = ImageFont.truetype(SUB, int(font.size * 0.3))
    for line in ["Same moves, new character.", "Right on your iPhone."]:
        d.text((x, y), line, font=small, fill=(215, 215, 225))
        y += small.size * 1.3
    y += small.size * 1.3
    ic = icon(int(small.size * 2.8), folder)
    im.paste(ic, (x, int(y)), ic)
    d.text((x + ic.width + small.size * 0.8, y + ic.height * 0.06), "Jutsu",
           font=ImageFont.truetype(FONT, int(small.size * 1.3)), fill=(255, 255, 255))
    d.text((x + ic.width + small.size * 0.8, y + ic.height * 0.58), "Unofficial Higgsfield client",
           font=ImageFont.truetype(SUB, int(small.size * 0.9)), fill=(170, 170, 185))
    px, py, pw, ph = phone
    b = bezel(ph)
    d.rounded_rectangle([px - b, py - b, px + pw + b, py + ph + b], pw // 8 + b, fill=(40, 40, 48))
    return im


def position(t, vw, start):
    """Where the line is at time t: off the right edge, halfway, then the left edge, and back for the loop."""
    ramp = lambda a, b: f"min(max(({t}-{a})/({b}-{a}),0),1)"
    half, whole, back = start, start + 1.3, LENGTH - 0.4
    return f"({vw}-{vw}/2*{ramp(half, half + 0.4)}-{vw}/2*{ramp(whole, whole + 0.4)}+{vw}*{ramp(back, LENGTH)})"


def build(out, w, h, text_box, phone, video_box, flow):
    folder = tempfile.mkdtemp()
    px, py, pw, ph = phone
    background(w, h, text_box, phone, os.path.dirname(out)).save(f"{folder}/bg.png")
    for name, _ in FLOW:
        Image.open(f"{flow}/{name}.png").convert("RGB").resize((pw, ph), Image.Resampling.LANCZOS).save(
            f"{folder}/{name}.png")
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], pw // 8, fill=255)
    mask.save(f"{folder}/mask.png")
    r = pw // 9
    tap = Image.new("RGBA", (r * 2, r * 2), (0, 0, 0, 0))
    ImageDraw.Draw(tap).ellipse([0, 0, r * 2 - 1, r * 2 - 1], fill=(255, 255, 255, 110), outline=(255, 255, 255, 230),
                                width=max(3, r // 10))
    tap.save(f"{folder}/tap.png")
    vx, vy, vw, vh = video_box
    size = int(min(h * 0.022, vw * 0.055))
    chip("YOUR CLIP", (0, 0, 0, 170), (255, 255, 255), size).save(f"{folder}/l.png")
    chip("NEW TAKE", LIME + (255,), (0, 0, 0), size).save(f"{folder}/r.png")
    left_w, right_w = Image.open(f"{folder}/l.png").width, Image.open(f"{folder}/r.png").width
    clip_mask = Image.new("L", (vw, vh), 0)
    ImageDraw.Draw(clip_mask).rounded_rectangle([0, 0, vw - 1, vh - 1], vw // 12, fill=255)
    clip_mask.save(f"{folder}/clip-mask.png")
    rw, rh = int(vw * RESULT_ZOOM), int(vh * RESULT_ZOOM)
    slow = f"setpts={SLOW}*PTS,fps=30,trim=0:{LENGTH},setpts=PTS-STARTPTS"
    inputs = ["-loop", "1", "-framerate", "30", "-t", str(LENGTH), "-i", f"{folder}/bg.png",
              "-i", take(SOURCE), "-i", take(RESULT)]
    for f in ["l", "r", "mask", "tap", "clip-mask"]:
        inputs += ["-loop", "1", "-framerate", "30", "-t", str(LENGTH), "-i", f"{folder}/{f}.png"]
    first_screen = 8  # after the background, the two takes, the chips, the masks and the tap
    for name, duration in FLOW:
        inputs += ["-loop", "1", "-framerate", "30", "-t", str(duration), "-i", f"{folder}/{name}.png"]
    p_blend, p_over = position("T", vw, DONE), position("t", vw, DONE)
    cy, margin = vy + size, size
    screens = "".join(f"[{first_screen + i}:v]fps=30,format=rgb24,setsar=1[screen{i}];" for i in range(len(FLOW)))
    gx, gy = px + GENERATE[0] * pw // 1320, py + GENERATE[1] * ph // 2868
    graph = ";".join([
        f"[1:v]{slow},scale={vw}:{vh}:force_original_aspect_ratio=increase,crop={vw}:{vh},format=gbrp[a]",
        f"[2:v]{slow},split=3[f1][f2][f3]",
        # Outside the safe area, where wider crops reach, the new take plays blurred and dim behind the glow.
        f"[f3]scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},boxblur=40:2,"
        "colorchannelmixer=rr=0.35:gg=0.35:bb=0.35,format=gbrp[haze]",
        "[0:v]format=gbrp[bgp]",
        "[bgp][haze]blend=all_mode=screen,format=rgb24[bg]",
        f"[f1]scale={rw}:{rh}:force_original_aspect_ratio=increase,crop={vw}:{vh}:(iw-{vw})/2:(ih-{vh})*0.3,"
        "format=gbrp[b]",
        f"[a][b]blend=all_expr='if(gte(X,{p_blend}),B,A)',format=rgba[v]",
        f"color=c=0xD4FF2A:s=8x{vh}:r=30:d={LENGTH},format=rgba[line]",
        f"[v][line]overlay=x='{p_over}-4':y=0:eval=frame:enable='between({p_over},1,{vw}-1)'[vl]",
        "[7:v]format=gray[cm]",
        "[vl][cm]alphamerge[vm]",
        f"[bg][vm]overlay=x={vx}:y={vy}:shortest=1[s]",
        f"[s][3:v]overlay=x='{vx}+{p_over}/2-w/2':y={cy}:eval=frame:"
        f"enable='gt({p_over},{left_w + 2 * margin})'[s3]",
        f"[s3][4:v]overlay=x='{vx}+({p_over}+{vw})/2-w/2':y={cy}:eval=frame:"
        f"enable='lt({p_over},{vw - right_w - 2 * margin})'[s4]",
        screens + f"[f2]trim={DONE}:{LENGTH},setpts=PTS-STARTPTS,scale={pw}:{ph}:force_original_aspect_ratio=increase,"
        f"crop={pw}:{ph},format=rgb24,setsar=1[sr]",
        "".join(f"[screen{i}]" for i in range(len(FLOW))) + f"[sr]concat=n={len(FLOW) + 1}:v=1:a=0,format=rgba[phone]",
        "[5:v]format=gray[m]",
        "[phone][m]alphamerge[pm]",
        f"[s4][pm]overlay=x={px}:y={py}:shortest=1[s5]",
        f"[s5][6:v]overlay=x={gx}-w/2:y={gy}-h/2:enable='between(t,{TAP[0]},{TAP[1]})'",
    ])
    subprocess.run([
        "ffmpeg", "-loglevel", "error", "-y", *inputs, "-filter_complex", graph, "-t", str(LENGTH), "-r", "30", "-an",
        "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", out,
    ], check=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(DONE + 1), "-i", out, "-frames:v", "1",
                    out.replace(".mp4", ".png")], check=True)


if __name__ == "__main__":
    folder, flow = sys.argv[1:3]
    os.makedirs(folder, exist_ok=True)
    # Everything sits in the safe area of Apple's templates, which every device's crop keeps: 2168 x 1030 centred
    # on 3840 x 2560 for search results (halved here), 1646 x 661 centred on 3840 x 1646 for the header.
    build(os.path.join(folder, "search-results-3x2.mp4"), 1920, 1280,
          *layout((418, 382, 1084, 515), 450, 34), flow)
    build(os.path.join(folder, "header-21x9.mp4"), 3840, 1646,
          *layout((1097, 493, 1646, 661), 700, 50), flow)
    os.remove(os.path.join(folder, "icon.png"))
