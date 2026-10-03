#!/usr/bin/env python3
"""Crop and encode native offscreen probe output for the public README.

Run the probes with WORKSPACE_EVIDENCE_DIR=/tmp/sz-readme-evidence, then:
python3 portable/mac/tests/refresh-readme-images.py /tmp/sz-readme-evidence
Requires Pillow; never captures the screen or reads user documents.
"""
import sys
from pathlib import Path
from PIL import Image

source = Path(sys.argv[1])
destination = Path(__file__).resolve().parents[3] / 'docs/images/portable'

def read(name):
    return Image.open(source / name).convert('RGB')

def save(image, name):
    image.save(destination / name, 'WEBP', quality=90, method=6)

save(read('reader-dark-find.png'), 'macos-main-window.webp')
save(read('reader-dark-1280.png').crop((0, 0, 2560, 920)), 'macos-groups.webp')
save(read('reader-light-markdown-1280.png'), 'macos-markdown.webp')
save(read('reader-dark-find.png'), 'macos-search-highlights.webp')
save(read('reader-light-markdown-1280.png').crop((0, 88, 480, 1470)), 'macos-chapters.webp')
save(read('collection.png'), 'macos-collection.webp')
save(read('collection-settings.png'), 'macos-collection-settings.webp')
save(read('reader-dark-history.png').crop((0, 0, 2560, 1050)), 'macos-history.webp')
code=read('reader-light-code.png')
save(code.crop((980, 280, 1840, 720)), 'macos-markdown-code.webp')
save(code.crop((980, 720, 1840, 1130)), 'macos-markdown-gantt.webp')
light=read('reader-light-code.png').crop((900, 175, 1860, 1500))
dark=read('reader-dark-code.png').crop((900, 175, 1860, 1500))
pair=Image.new('RGB', (light.width+dark.width+16, light.height), '#25282c')
pair.paste(light,(0,0)); pair.paste(dark,(light.width+16,0))
save(pair, 'macos-dark-theme.webp')
print('Wrote 11 README images from native offscreen components.')
