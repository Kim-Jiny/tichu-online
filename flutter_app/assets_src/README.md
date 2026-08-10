# assets_src

Original artwork the shipped icons are derived from.

`flutter_app/assets/icons/` is registered wholesale in pubspec.yaml, so
anything left in there is bundled into the app — a 1.2 MB master PNG sitting
next to its 7 KB webp would ship both. Masters live here instead, outside every
bundled path, so they stay in the repo without riding along in the build.

| source | shipped | saving |
| --- | --- | --- |
| `allowBotReplacement.png` (1536×1024 RGBA) | `assets/icons/allowBotReplacement.webp` (144×115) | 1.2 MB → 7.6 KB |
| `lankIcon.png` (1536×1024 RGBA) | `assets/icons/lankIcon.webp` (144×125) | 1.4 MB → 11 KB |

## Converting a new one

```bash
cd flutter_app/assets_src
python3 - <<'EOF'
from PIL import Image
NAME = 'allowBotReplacement'          # <- change me
src = Image.open(f'{NAME}.png').convert('RGBA')
mask = src.getchannel('A').point(lambda v: 255 if v > 8 else 0)
art = src.crop(mask.getbbox())
w, h = art.size
scale = 144 / max(w, h)
art.resize((round(w * scale), round(h * scale)), Image.LANCZOS).save('_tmp.png')
EOF
cwebp -q 90 -alpha_q 100 _tmp.png -o ../assets/icons/<NAME>.webp
rm _tmp.png
```

144px on the long edge matches the existing icon set (goldIcon is 144) and
covers a 30px slot at 3x with room to spare.

## Two ways this went wrong before

- **Don't flatten with `.convert('RGB')`.** It composites the alpha onto black,
  and the icon arrives with a black tile behind it.
- **Trim on a threshold (`alpha > 8`), not on `getbbox()` alone.** These
  renders carry a faint glow that bleeds nearly to the frame edge, so a plain
  `getbbox()` keeps ~20% of the width as margin and the artwork renders
  shrunken inside its own padding. Don't pad the result to a square either —
  both glyphs are wider than tall, and the padding is dead space in every slot
  that uses them. Ship the natural aspect and let `BoxFit.contain` place it.
