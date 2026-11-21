"""Renders IMDb's logo (brand/ratings/imdb.svg) to the PNG the app shows next to its ratings
(assets/images/ratings/imdb.png, 128 px high, transparent background).

    pip install cairosvg
    python3 brand/tools/rating_logos.py

Prints the logo's width / height: `RatingLogo.imdbAspectRatio` (lib/features/ratings/rating_view.dart).
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
