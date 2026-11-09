# Builds the Vixeo logo (mark + "Vixeo" in Sora ExtraBold, as outlines) and its icons, from the
# measurements of the reference image. Units: 1 = 1 px of the reference, mark 80 high.
import math, sys
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

FONT = sys.argv[1]
OUT = sys.argv[2]
TEXT = '#F1F5F2'   # VxColors.text
ACCENT = '#2EE58A'  # VxColors.accent
BG = '#070A08'      # VxColors.background

# The V: an outer triangle minus an inner one (both arms 26 wide), symmetric around x = 53.
V = [(0, 0), (26, 0), (53, 40.75), (80, 0), (106, 0), (53, 80)]
V_ROUND = [2.2, 1.6, 1.4, 1.6, 2.2, 3.2]
# The green triangle: its left edge parallel to the V's right arm, 14 away.
TRI = [(104.1, 24), (117, 45.5), (73, 71)]
TRI_ROUND = [2.6, 2.6, 2.6]


def rounded(points, radii):
    """Closed path of a polygon with rounded corners (a quadratic curve at each corner)."""
    n = len(points)
    def towards(p, q, d):
        dx, dy = q[0] - p[0], q[1] - p[1]
        length = math.hypot(dx, dy)
        return (p[0] + dx * d / length, p[1] + dy * d / length)
    parts = []
    for i, p in enumerate(points):
        prev, nxt = points[i - 1], points[(i + 1) % n]
        a, b = towards(p, prev, radii[i]), towards(p, nxt, radii[i])
        parts.append((a, p, b))
    f = lambda v: f'{v:.2f}'.rstrip('0').rstrip('.')
    d = f'M{f(parts[0][2][0])} {f(parts[0][2][1])}'
    for a, p, b in parts[1:] + parts[:1]:
        d += f'L{f(a[0])} {f(a[1])}Q{f(p[0])} {f(p[1])} {f(b[0])} {f(b[1])}'
    return d + 'Z'


V_PATH = rounded(V, V_ROUND)
TRI_PATH = rounded(TRI, TRI_ROUND)

# "Vixeo", shaped with HarfBuzz (Sora's kerning), as outlines: no font needed to show the logo.
blob = hb.Blob.from_file_path(FONT)
font = hb.Font(hb.Face(blob))
buf = hb.Buffer()
buf.add_str('Vixeo')
buf.guess_segment_properties()
hb.shape(font, buf, {'kern': True})
tt = TTFont(FONT)
glyphs = tt.getGlyphSet()
order = tt.getGlyphOrder()
infos, positions = buf.glyph_infos, buf.glyph_positions

# Ink box of the word, in font units.
x = 0
xmin = ymin = 1e9
xmax = ymax = -1e9
for info, pos in zip(infos, positions):
    bp = BoundsPen(glyphs)
    glyphs[order[info.codepoint]].draw(TransformPen(bp, (1, 0, 0, 1, x + pos.x_offset, pos.y_offset)))
    if bp.bounds:
        xmin, ymin = min(xmin, bp.bounds[0]), min(ymin, bp.bounds[1])
        xmax, ymax = max(xmax, bp.bounds[2]), max(ymax, bp.bounds[3])
    x += pos.x_advance

# Measured in the reference: the word's ink is 223 wide, starts 20 after the mark and sits on a
# baseline at y 67.1 (the mark is 0 to 80 high: cap height about 0.69 of the mark).
INK_WIDTH, GAP, BASELINE = 223.0, 20.0, 67.1
scale = INK_WIDTH / (xmax - xmin)
left = 117 + GAP - xmin * scale
pen = SVGPathPen(glyphs)
x = 0
for info, pos in zip(infos, positions):
    t = (scale, 0, 0, -scale, left + (x + pos.x_offset) * scale, BASELINE - pos.y_offset * scale)
    glyphs[order[info.codepoint]].draw(TransformPen(pen, t))
    x += pos.x_advance
WORD_PATH = pen.getCommands()
WIDTH = 117 + GAP + INK_WIDTH
cap = tt['OS/2'].sCapHeight * scale
print(f'font size {scale * 1000:.1f}, cap height {cap:.1f} (mark 80: {cap / 80:.3f}), logo {WIDTH:.1f} x 80')


def mark(fill_v=TEXT, fill_tri=ACCENT):
    return f'<path fill="{fill_v}" d="{V_PATH}"/><path fill="{fill_tri}" d="{TRI_PATH}"/>'


def svg(view, body, title='Vixeo'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" role="img" aria-label="{title}">'
            f'<title>{title}</title>{body}</svg>\n')


def write(name, content):
    with open(f'{OUT}/{name}', 'w') as fh:
        fh.write(content)

# Logo for dark backgrounds (the app, the site): white V and word, green triangle.
write('vixeo-logo.svg', svg(f'0 0 {WIDTH:.1f} 80', mark() + f'<path fill="{TEXT}" d="{WORD_PATH}"/>'))
# The mark alone.
write('vixeo-mark.svg', svg('0 0 117 80', mark()))
# Logo on the background color (previews, documents, social images).
pad = 40
write('vixeo-logo-fond.svg', svg(
    f'{-pad} {-pad} {WIDTH + 2 * pad:.1f} {80 + 2 * pad}',
    f'<rect x="{-pad}" y="{-pad}" width="{WIDTH + 2 * pad:.1f}" height="{80 + 2 * pad}" fill="{BG}"/>'
    + mark() + f'<path fill="{TEXT}" d="{WORD_PATH}"/>'))


def icon(size_ratio, radius_ratio, name):
    """The mark centered on a square of the background color; [size_ratio]: mark width / side."""
    side = 117 / size_ratio
    # Optical center: the V's weight is on the left, the triangle on the right; center the box.
    x0 = (side - 117) / 2
    y0 = (side - 80) / 2
    r = side * radius_ratio
    body = (f'<rect width="{side:.2f}" height="{side:.2f}" rx="{r:.2f}" fill="{BG}"/>'
            f'<g transform="translate({x0:.2f} {y0:.2f})">{mark()}</g>')
    write(name, svg(f'0 0 {side:.2f} {side:.2f}', body))

icon(0.78, 0.22, 'favicon.svg')            # browser tab: big mark, rounded square
icon(0.62, 0.0, 'icon.svg')                 # app icons (192, 512, Apple): square, the system rounds it
icon(0.50, 0.0, 'icon-maskable.svg')        # Android maskable: mark inside the safe circle (80 %)
