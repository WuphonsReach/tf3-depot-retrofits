"""Draw the mod's preview image (1920x1080 JPG, the size other mods ship) from SVG with rsvg-convert and Lato.

A retrofitted depot with its maintenance radius drawn as rings (the stock radius dashed, the retrofitted one amber),
buses around it, and the five level trees listed on the left. The upper right corner is kept clear for a version number.

Usage: python3 tools/make_preview.py [OUT_FILE] [--version 0.5] [--keep-svg SVG_FILE]
--keep-svg also writes the SVG the image is rendered from (for example to local/preview/cover.svg); keep it out of depot_retrofits_1/.
OUT_FILE defaults to depot_retrofits_1/_metadata/0.jpg, the cover (the uploader's Preview slot); see docs/publishing.md.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

W, H = 1920, 1080

GREEN, AMBER = "#6cc04a", "#f2b33d"
BLUE, TEAL, VIOLET = "#4fa3e0", "#45c1a4", "#a58be6"
INK = "#152031"

# The background's gradient and glow, drawn by background(); tools/make_gallery.py lays its cards on the same background.
BACKGROUND_DEFS = '''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22334b"/><stop offset="1" stop-color="#0e1521"/></linearGradient>
  <radialGradient id="glow" cx="0.62" cy="0.78" r="0.55"><stop offset="0" stop-color="#3a5a7e" stop-opacity=".45"/><stop offset="1" stop-color="#3a5a7e" stop-opacity="0"/></radialGradient>'''


def darker(color, k=0.55):
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    return f"#{int(r * k):02x}{int(g * k):02x}{int(b * k):02x}"


def text(x, y, s, size=42, anchor="start", weight=700, fill="#fff", opacity=.88):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="Lato" font-weight="{weight}" font-size="{size}" '
            f'fill="{fill}" fill-opacity="{opacity}">{s}</text>')


def background():
    out = [f'<rect width="{W}" height="{H}" fill="url(#bg)"/>', f'<rect width="{W}" height="{H}" fill="url(#glow)"/>']
    for x in range(0, W + 1, 160):
        out.append(f'<line x1="{x}" y1="0" x2="{x}" y2="{H}" stroke="#fff" stroke-opacity="0.045" stroke-width="2"/>')
    for y in range(0, H + 1, 160):
        out.append(f'<line x1="0" y1="{y}" x2="{W}" y2="{y}" stroke="#fff" stroke-opacity="0.045" stroke-width="2"/>')
    return "\n".join(out)


# ---- tree icons, drawn on a 64 x 64 grid centred on (0, 0) ----

def glyph(key, ink):
    if key == "radius":
        return (f'<circle r="27" fill="none" stroke="{ink}" stroke-width="5" stroke-dasharray="8 6"/>'
                f'<circle r="15" fill="none" stroke="{ink}" stroke-width="5"/><circle r="6" fill="{ink}"/>')
    if key == "vehicles":
        return (f'<rect x="-20" y="-27" width="40" height="46" rx="8" fill="none" stroke="{ink}" stroke-width="5"/>'
                f'<rect x="-13" y="-20" width="26" height="15" rx="3" fill="{ink}"/>'
                f'<circle cx="-10" cy="9" r="3.5" fill="{ink}"/><circle cx="10" cy="9" r="3.5" fill="{ink}"/>'
                f'<rect x="-17" y="19" width="8" height="9" rx="2" fill="{ink}"/><rect x="9" y="19" width="8" height="9" rx="2" fill="{ink}"/>')
    if key == "pollution":
        return (f'<circle cx="-12" cy="2" r="12" fill="{ink}"/><circle cx="3" cy="-8" r="15" fill="{ink}"/>'
                f'<circle cx="17" cy="4" r="10" fill="{ink}"/><rect x="-12" y="2" width="29" height="12" fill="{ink}"/>'
                f'<path d="M -4 20 L 4 28 L 12 20" fill="none" stroke="{ink}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>')
    if key == "noise":
        return (f'<path d="M -26 -9 L -14 -9 L 0 -22 L 0 22 L -14 9 L -26 9 Z" fill="{ink}" stroke="{ink}" stroke-width="3" stroke-linejoin="round"/>'
                f'<path d="M 9 -10 Q 16 0 9 10" fill="none" stroke="{ink}" stroke-width="5" stroke-linecap="round"/>'
                f'<path d="M 16 -19 Q 29 0 16 19" fill="none" stroke="{ink}" stroke-width="5" stroke-linecap="round"/>')
    if key == "upkeep":
        return (f'<circle r="25" fill="none" stroke="{ink}" stroke-width="5"/>'
                f'<text y="12" text-anchor="middle" font-family="Lato" font-weight="900" font-size="34" fill="{ink}">$</text>')
    raise ValueError(key)


def badge(cx, cy, r, key, color):
    """A tree's icon on a coloured disc with a white rim, in the style of Best Before's faces."""
    k = r * 1.45 / 64
    return f'''<g filter="url(#shadow)">
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}" stroke="#fff" stroke-width="{max(4, r * .11):.1f}"/>
  <ellipse cx="{cx - r * .3:.1f}" cy="{cy - r * .5:.1f}" rx="{r * .35:.1f}" ry="{r * .18:.1f}" fill="#fff" opacity=".25"/>
  <g transform="translate({cx} {cy}) scale({k:.3f})">{glyph(key, INK)}</g>
</g>'''


# ---- the depot and the buses, flat style: fill, darker same-hue outline, light highlight ----

def depot(cx, ground, s=1.0):
    """A retrofitted road depot seen from the front: brick shed with green trim, sawtooth roof with solar panels,
    a clean chimney, three roller doors with the middle one open on a bus. Local units: 560 wide, the origin at the
    middle of the ground line."""
    wall, edge, brick = "#a8705a", "#55311f", "#8c5641"
    roof, roof_edge, door, slat, glass = "#748391", "#36424e", "#4f6d88", "#6f8ca6", "#9fd6f2"
    out = ['<ellipse cx="0" cy="6" rx="330" ry="26" fill="#000" opacity=".35"/>']
    # chimney behind the roof, two light puffs
    out.append(f'<rect x="186" y="-392" width="42" height="150" fill="#7d5a4a" stroke="{edge}" stroke-width="6"/>')
    out.append(f'<rect x="180" y="-404" width="54" height="18" fill="#7d5a4a" stroke="{edge}" stroke-width="6"/>')
    out += [f'<circle cx="{x}" cy="{y}" r="{r}" fill="#d6e0ea" opacity="{o}"/>' for x, y, r, o in ((212, -428, 16, .5), (232, -462, 12, .35))]
    # sawtooth roof, four teeth, glazing on the steep side, a solar panel on each slope
    for i in range(4):
        x0 = -280 + i * 140
        out.append(f'<path d="M {x0} -230 L {x0 + 140} -302 L {x0 + 140} -230 Z" fill="{roof}" stroke="{roof_edge}" '
                   f'stroke-width="6" stroke-linejoin="round"/>')
        out.append(f'<rect x="{x0 + 126}" y="-292" width="11" height="58" fill="{glass}"/>')
        ax, ay, bx, by = x0 + 14, -237, x0 + 118, -290
        out.append(f'<path d="M {ax} {ay} L {bx} {by} L {bx - 7} {by - 14} L {ax - 7} {ay - 14} Z" fill="#2b4d86" '
                   f'stroke="#1a2f55" stroke-width="3" stroke-linejoin="round"/>')
        for t in (.33, .66):
            px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            out.append(f'<line x1="{px:.1f}" y1="{py:.1f}" x2="{px - 7:.1f}" y2="{py - 14:.1f}" stroke="#7fb0ff" stroke-width="2"/>')
    out.append(f'<rect x="-292" y="-240" width="584" height="16" rx="3" fill="{roof}" stroke="{roof_edge}" stroke-width="6"/>')
    # walls with brick courses and the green trim
    out.append(f'<rect x="-280" y="-224" width="560" height="224" fill="{wall}" stroke="{edge}" stroke-width="6"/>')
    out += [f'<line x1="-277" y1="{y}" x2="277" y2="{y}" stroke="{brick}" stroke-width="3" stroke-opacity=".7"/>' for y in range(-201, 0, 23)]
    out.append(f'<rect x="-280" y="-224" width="560" height="12" fill="{GREEN}"/>')
    # sign
    out.append(f'<rect x="-130" y="-208" width="260" height="42" rx="6" fill="{GREEN}" stroke="{edge}" stroke-width="4"/>')
    out.append(f'<text x="0" y="-177" text-anchor="middle" font-family="Lato" font-weight="900" font-size="30" fill="{INK}" '
               f'letter-spacing="6">DEPOT</text>')
    # roller doors, the middle one open
    for dx in (-170, 0, 170):
        x, y, w, h = dx - 66, -150, 132, 150
        if dx == 0:
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#141b24" stroke="{edge}" stroke-width="6"/>')
            out.append(f'<g transform="translate({dx} -58) scale(1.7)">{glyph("vehicles", GREEN)}</g>')
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="26" fill="{door}" stroke="{edge}" stroke-width="6"/>')
            continue
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{door}" stroke="{edge}" stroke-width="6"/>')
        out += [f'<line x1="{x + 3}" y1="{yy}" x2="{x + w - 3}" y2="{yy}" stroke="{slat}" stroke-width="4"/>' for yy in range(y + 15, 0, 15)]
    out.append('<rect x="-276" y="-220" width="16" height="216" fill="#fff" opacity=".08"/>')
    return f'<g transform="translate({cx} {ground}) scale({s})">{"".join(out)}</g>'


def bus(cx, ground, s=1.0, color=GREEN, facing=1):
    edge = darker(color)
    windows = "".join(f'<rect x="{x}" y="-90" width="34" height="32" rx="4" fill="#bfe3f5"/>' for x in range(-104, 60, 42))
    return f'''<g transform="translate({cx} {ground}) scale({s * facing} {s})">
  <ellipse cx="0" cy="2" rx="130" ry="10" fill="#000" opacity=".35"/>
  <rect x="-124" y="-104" width="248" height="88" rx="14" fill="{color}" stroke="{edge}" stroke-width="5"/>
  {windows}
  <path d="M 84 -90 L 112 -90 Q 118 -90 118 -82 L 118 -50 L 84 -50 Z" fill="#bfe3f5"/>
  <rect x="-120" y="-44" width="240" height="8" fill="#fff" opacity=".45"/>
  <circle cx="-74" cy="-14" r="18" fill="#1f262f"/><circle cx="-74" cy="-14" r="7" fill="#9aa7b4"/>
  <circle cx="74" cy="-14" r="18" fill="#1f262f"/><circle cx="74" cy="-14" r="7" fill="#9aa7b4"/>
  <circle cx="114" cy="-30" r="5" fill="#ffe7a3"/>
</g>'''


def ring(cx, cy, rx, color="#fff", opacity=.4, width=5, dash=""):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{rx * .3:.1f}" fill="none" stroke="{color}" '
            f'stroke-opacity="{opacity}" stroke-width="{width}"{d}/>')


def scene():
    """The depot right of centre with both radius rings: the stock one dashed, the retrofitted one wider and in the
    radius tree's colour, so it reads as that tree's work."""
    cx, g = 1270, 840
    r = 610
    return "\n".join([
        f'<ellipse cx="{cx}" cy="{g - 30}" rx="{r}" ry="{r * .3:.1f}" fill="{BLUE}" fill-opacity=".08"/>',
        ring(cx, g - 30, r, BLUE, .9, 8),
        ring(cx, g - 30, r, BLUE, .25, 26),
        ring(cx, g - 30, round(r / 1.75), "#fff", .45, 5, "18 14"),
        text(cx, g + 110, "stock radius", 32, "middle", 700, "#fff", .6),
        bus(cx - 520, g + 110, .7, BLUE),
        bus(cx + 470, g + 30, .62, GREEN, -1),
        depot(cx, g),
        bus(cx - 300, g + 175, .78, GREEN),
    ])


def trees():
    """Left column below the title: the five level trees, one row each (badge and what it does)."""
    rows = [("radius", "Wider maintenance radius", BLUE), ("vehicles", "More vehicles maintained", GREEN),
            ("pollution", "Less pollution", TEAL), ("noise", "Less noise", VIOLET), ("upkeep", "Lower upkeep", AMBER)]
    out = []
    for i, (key, label, color) in enumerate(rows):
        y = 450 + i * 96
        out.append(badge(110, y, 36, key, color))
        out.append(text(170, y + 14, label, 40))
    return "\n".join(out)


def build(version=None):
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'''<defs>
  {BACKGROUND_DEFS}
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="6" stdDeviation="7" flood-color="#000" flood-opacity=".45"/></filter>
</defs>''',
        background(),
        scene(),
        '<g filter="url(#shadow)"><text x="70" y="220" font-family="Lato" font-weight="900" font-size="156" fill="#fff" letter-spacing="2">DEPOT RETROFITS</text></g>',
        f'<text x="76" y="310" font-family="Lato" font-weight="800" font-size="62" fill="{AMBER}" letter-spacing="11">LEVEL UP YOUR DEPOTS</text>',
        trees(),
    ]
    if version:  # upper right corner, kept clear for it
        parts.append(f'<text x="{W - 56}" y="72" text-anchor="end" font-family="Lato" font-weight="700" font-size="54" fill="#fff" fill-opacity=".85">v{version}</text>')
    parts.append("</svg>")
    return "\n".join(parts)


def main():
    args = sys.argv[1:]
    version = None
    if "--version" in args:
        i = args.index("--version")
        version = args[i + 1]
        del args[i:i + 2]
    keep_svg = None
    if "--keep-svg" in args:
        i = args.index("--keep-svg")
        keep_svg = Path(args[i + 1])
        del args[i:i + 2]
    out = Path(args[0] if args else Path(__file__).resolve().parent.parent / "depot_retrofits_1/_metadata/0.jpg")
    out.parent.mkdir(parents=True, exist_ok=True)
    from PIL import Image
    with tempfile.TemporaryDirectory() as tmp:
        svg, png = Path(tmp) / "preview.svg", Path(tmp) / "preview.png"
        svg.write_text(build(version))
        if keep_svg:
            keep_svg.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(svg, keep_svg)
        subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(png), str(svg)], check=True)
        Image.open(png).convert("RGB").save(out, quality=92, optimize=True, progressive=True)
    print(out)


if __name__ == "__main__":
    main()
