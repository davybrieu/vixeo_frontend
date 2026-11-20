"""Renders the logos of the rating sites (brand/ratings/*.svg) to the PNGs the app shows
(assets/images/ratings/*.png, 128 px high, transparent background).

    pip install cairosvg
    python3 brand/tools/rating_logos.py

Prints each logo's width / height: `RatingSource.logoAspect` (lib/features/ratings/rating_source.dart).
"""

import pathlib
import re

import cairosvg

ROOT = pathlib.Path(__file__).resolve().parents[2]
HEIGHT = 128

for svg in sorted((ROOT / 'brand' / 'ratings').glob('*.svg')):
    text = svg.read_text()
    _, _, width, height = (float(v) for v in re.search(r'viewBox="([^"]+)"', text).group(1).split())
    aspect = width / height
    target = ROOT / 'assets' / 'images' / 'ratings' / f'{svg.stem}.png'
    cairosvg.svg2png(
        bytestring=text.encode(),
        write_to=str(target),
        output_height=HEIGHT,
        output_width=round(HEIGHT * aspect),
    )
    print(f'{svg.stem}: {round(HEIGHT * aspect)} x {HEIGHT}, aspect {aspect:.3f}')
