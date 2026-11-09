# After raster.js: the favicon.ico (16, 32, 48) of the web app and of the site, and the opaque
# app icons saved without alpha (iOS refuses an app icon with an alpha channel).
# Run from the repository root: python3 brand/tools/finish_icons.py
import glob
from PIL import Image

sizes = [Image.open(f'brand/icons/favicon-{n}.png').convert('RGBA') for n in (16, 32)]
big = Image.open('web/favicon.png').convert('RGBA')
big.save('brand/icons/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)], append_images=sizes)
big.save('web/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)], append_images=sizes)

opaque = glob.glob('ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png') + glob.glob('web/icons/*.png')
for path in opaque:
    Image.open(path).convert('RGB').save(path)
print(f'favicon.ico, {len(opaque)} opaque icons')
