"""Draw a gallery image for the mod's listing (1920x1080 JPG): screenshots of the building window laid as a loose pile of cards
on the preview image's background (tools/make_preview.py), each a little off upright.

Each screenshot is a hand-cropped shot of one window. The window is cut out along its light outline, the map around it
removed, and the corners rounded; the corner with the close button is kept as shot, since the button stands out of the
window. Cards keep their slant and position from the arguments, so a new set of screenshots can be laid out the same way.

Usage: python3 tools/make_gallery.py OUT_FILE CARD.png[:angle[:dy[:slot]]] ...
Cards are listed from the bottom of the pile to the top. angle is in degrees (positive tilts left), dy moves the card down in
pixels, slot is its place from the left (default: its place in the list). Needs rsvg-convert, for the background.

The current listing's 1.jpg (three Retrofit tabs) was made from the crops in tools/gallery/ with:
python3 tools/make_gallery.py depot_retrofits_1/_metadata/1.jpg tools/gallery/maintenance_building.png:2.5:16:0 tools/gallery/train_depot.png:-2.5:22:2 tools/gallery/ship_depot.png:-1:-4:1
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_preview  # noqa: E402

W, H = make_preview.W, make_preview.H
CARD_H = 880
SPACING = 560  # between card centres; a card is about 550 wide, so neighbours just overlap once tilted
RADIUS = 22  # the window's rounded corners, in screenshot pixels
CLOSE_CORNER = 120  # the top-right square that holds the window's close button, in screenshot pixels


def near_outline(p):
    """The light outline around the game's windows (about #545858)."""
    r, g, b = p[:3]
    return 0x4c <= r <= 0x5e and 0x50 <= g <= 0x60 and 0x52 <= b <= 0x62


def window_box(im):
    """The window's outline on each side, found along the middle row and column; the image edge where no outline shows."""
    w, h = im.size
    px = im.load()

    def scan(coords):
        for i, (x, y) in enumerate(coords):
            if near_outline(px[x, y]):
                return i
        return 0

    left = scan([(x, h // 2) for x in range(0, 40)])
    right = scan([(x, h // 2) for x in range(w - 1, w - 41, -1)])
    top = scan([(w // 2, y) for y in range(0, 40)])
    bottom = scan([(w // 2, y) for y in range(h - 1, h - 41, -1)])
    return (left, top, w - right, h - bottom)


def outside_window(im):
    """A mask of the map left around the window.

    The outline, thickened to close gaps at the rounded corners, is a wall. Every region on the image edge gets its own flood
    fill; all but the largest (the window itself, which touches an edge where the screenshot cut through it) are map.
    """
    w, h = im.size
    wall = Image.new("L", im.size, 0)
    src, dst = im.load(), wall.load()
    for y in range(h):
        for x in range(w):
            if near_outline(src[x, y]):
                dst[x, y] = 255
    work = wall.filter(ImageFilter.MaxFilter(5))
    px = work.load()
    label = 0
    edge = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    for xy in edge:
        if px[xy] == 0 and label < 250:
            label += 1
            ImageDraw.floodfill(work, xy, label, thresh=0)
    counts = work.histogram()
    keep = max(range(1, label + 1), key=lambda k: counts[k]) if label else None
    out = work.point(lambda v: 255 if 1 <= v <= label and v != keep else 0)
    out = out.filter(ImageFilter.MaxFilter(5))  # also the map pixels under the thickened wall
    out.paste(0, (w - CLOSE_CORNER, 0, w, CLOSE_CORNER))
    return out


def card(path):
    im = Image.open(path).convert("RGBA")
    im = im.crop(window_box(im))
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), RADIUS, fill=255)
    mask.paste(0, mask=outside_window(im))
    im.putalpha(mask)
    return im.resize((round(im.width * CARD_H / im.height), CARD_H), Image.LANCZOS)


def background():
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
           f'<defs>{make_preview.BACKGROUND_DEFS}</defs>{make_preview.background()}</svg>')
    with tempfile.TemporaryDirectory() as tmp:
        src, png = Path(tmp) / "background.svg", Path(tmp) / "background.png"
        src.write_text(svg)
        subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(png), str(src)], check=True)
        return Image.open(png).convert("RGBA")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out, specs = Path(sys.argv[1]), sys.argv[2:]
    image = background()
    for i, spec in enumerate(specs):
        path, *rest = spec.split(":")
        angle = float(rest[0]) if len(rest) > 0 else 0.0
        dy = int(rest[1]) if len(rest) > 1 else 0
        slot = int(rest[2]) if len(rest) > 2 else i
        c = card(path).rotate(angle, resample=Image.BICUBIC, expand=True)
        x = round(W / 2 + (slot - (len(specs) - 1) / 2) * SPACING) - c.width // 2
        y = (H - c.height) // 2 + dy
        # The preview's drop shadow (its "shadow" filter): 6 pixels down, blur 7, black at 45%.
        shadow = Image.new("RGBA", c.size, (0, 0, 0, 0))
        shadow.putalpha(c.getchannel("A").point(lambda a: a * 0.45))
        image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(7)), (x, y + 6))
        image.alpha_composite(c, (x, y))
    out.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(out, quality=92, optimize=True, progressive=True)
    print(out)


if __name__ == "__main__":
    main()
