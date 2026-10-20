"""產生內嵌字型子集：Big5 常用字 + 專案內所有文字用到的字元。
用法：python3 tools/make_font_subset.py <來源 Noto Sans CJK TC 字型(.otf/.ttc)> [ttc 索引]
需要：pip install fonttools
"""
import sys, pathlib
from fontTools import subset
from fontTools.ttLib import TTFont, TTCollection

root = pathlib.Path(__file__).resolve().parent.parent
src = sys.argv[1]
chars = set(chr(c) for c in range(0x20, 0x7f))
for hi in range(0xA1, 0xC7):
    for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
        try:
            chars.add(bytes([hi, lo]).decode('big5'))
        except Exception:
            pass
chars |= set("★☆✓✗×÷→←↑↓·•…—–「」『』（）：；，。、！？％＋－＝／〈〉《》【】①②③④⑤⑥⑦⑧⑨⑩▲▼◆◇○●□■♥⚔⏸▶⏩")
for c in range(0xFF01, 0xFF5F):
    chars.add(chr(c))
for p in list(root.rglob('*.json')) + list(root.rglob('*.gd')) + list(root.rglob('*.tscn')) + list(root.rglob('*.md')):
    if '.godot' in p.parts:
        continue
    chars |= set(p.read_text(encoding='utf-8'))
chars = {c for c in chars if ord(c) >= 0x20}
if src.endswith('.ttc'):
    font = TTCollection(src).fonts[int(sys.argv[2]) if len(sys.argv) > 2 else 3]
else:
    font = TTFont(src)
opts = subset.Options()
opts.layout_features = ['*']
opts.name_IDs = ['*']
opts.notdef_outline = True
sub = subset.Subsetter(opts)
sub.populate(unicodes=[ord(c) for c in chars])
sub.subset(font)
out = root / 'assets' / 'fonts' / 'NotoSansTC-Subset.otf'
font.save(str(out))
print(f'{len(chars)} 字元 → {out} ({out.stat().st_size // 1024} KB)')
