#!/usr/bin/env python3
"""Нарезает иконки приложения из assets/icon/app_icon.png.

Запуск: python3 tool/make_icons.py

Исходник должен быть квадратным и «в край»: без своих закруглённых углов и без
прозрачности. iOS и Android накладывают маску сами, а собственные углы после
этого дают светлые уголки по краям. Прозрачность в иконке iOS запрещена —
App Store отклоняет сборку с альфа-каналом в иконке.
"""

import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'assets/icon/app_icon.png')
IOS_SET = os.path.join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')

# Плотности Android для legacy-иконки.
ANDROID = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}


def load_source():
    im = Image.open(SOURCE)
    if im.width != im.height:
        sys.exit(f'иконка должна быть квадратной, а не {im.width}x{im.height}')
    if im.width < 1024:
        sys.exit(f'исходник {im.width}px — для App Store нужен минимум 1024px')
    return im.convert('RGB')


def write(im, path, px):
    im.resize((px, px), Image.LANCZOS).save(path, 'PNG', optimize=True)


def main():
    src = load_source()

    sizes = {}
    contents = json.load(open(os.path.join(IOS_SET, 'Contents.json')))
    for entry in contents['images']:
        side = float(entry['size'].split('x')[0])
        scale = int(entry['scale'][0])
        sizes[entry['filename']] = round(side * scale)

    for filename, px in sorted(sizes.items()):
        write(src, os.path.join(IOS_SET, filename), px)
    print(f'iOS: {len(sizes)} файлов в AppIcon.appiconset')

    for folder, px in ANDROID.items():
        path = os.path.join(ROOT, 'android/app/src/main/res', folder,
                            'ic_launcher.png')
        write(src, path, px)
    print(f'Android: {len(ANDROID)} плотностей')


if __name__ == '__main__':
    main()
