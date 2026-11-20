# After raster.js: the favicon.ico (16, 32, 48) of the site, the icon of the Windows app
# (16 to 256) and the opaque app icons saved without alpha (iOS refuses an app icon with an alpha
# channel). Run from the repository root: python3 brand/tools/finish_icons.py
import glob
from PIL import Image

sizes = [Image.open(f'brand/icons/favicon-{n}.png').convert('RGBA') for n in (16, 32)]
big = Image.open('brand/icons/favicon-48.png').convert('RGBA')
big.save('brand/icons/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)], append_images=sizes)

windows = Image.open('brand/icons/icon-rounded-256.png').convert('RGBA')
windows.save(
    'windows/runner/resources/app_icon.ico',
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

opaque = glob.glob('ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png')
for path in opaque:
    Image.open(path).convert('RGB').save(path)
print(f'favicon.ico, app_icon.ico, {len(opaque)} opaque icons')
