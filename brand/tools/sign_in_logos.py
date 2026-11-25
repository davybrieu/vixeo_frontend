"""Renders the logos of « Continuer avec Google / Apple » (brand/sign-in/*.svg) to the PNGs of the
buttons of the sign-in page (assets/images/sign_in/<provider>.png, 96 px, transparent background).

    pip install cairosvg
    python3 brand/tools/sign_in_logos.py
"""

import pathlib

import cairosvg

ROOT = pathlib.Path(__file__).resolve().parents[2]
SIZE = 96

for svg in sorted((ROOT / 'brand' / 'sign-in').glob('*.svg')):
    target = ROOT / 'assets' / 'images' / 'sign_in' / f'{svg.stem}.png'
    cairosvg.svg2png(bytestring=svg.read_bytes(), write_to=str(target), output_width=SIZE, output_height=SIZE)
    print(f'{svg.stem}: {SIZE} x {SIZE}')
