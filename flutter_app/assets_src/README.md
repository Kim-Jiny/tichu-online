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
| `tichuSymbol.png` (1536×1024 RGBA) | `assets/icons/tichuSymbol.webp` (112×144) | 1.1 MB → 6.4 KB |
| `skSymbol.png` (1024×1536 RGBA) | `assets/icons/skSymbol.webp` (88×144) | 1.1 MB → 6.1 KB |
| `mtSymbol.png` (1024×1536 RGBA) | `assets/icons/mtSymbol.webp` (114×144) | 1.1 MB → 3.6 KB |
| `llSymbol.png` (1024×1536 RGBA) | `assets/icons/llSymbol.webp` (144×131) | 965 KB → 3.3 KB |
| `coupon.png` (1254×1254 **RGB**) | `assets/icons/coupon.webp` (144×92) | 830 KB → 8.7 KB |

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

## 변환 후에는 `flutter run` 을 다시 띄운다

원본을 `assets/icons/` 에서 여기로 옮기는 순간, 돌고 있는 `flutter run` 은
세션 시작 때 만든 애셋 목록을 그대로 들고 있어서 없어진 파일을 찾다 죽는다.

```
Could not update files on device: PathNotFoundException:
Cannot open file, path = '.../assets/icons/coupon.png'
```

핫리로드로도 핫리스타트로도 안 되고, 세션을 껐다 켜야 한다. 두 번 겪었다
(게임 심볼 4종, coupon).

## Two ways this went wrong before

- **A master with no alpha at all needs the background keyed out.** `coupon.png`
  arrived as RGB artwork on a black field. Trimming does nothing to that — the
  black is opaque — and the icon lands as a black tile on a cream card. Build
  the alpha from luminance instead of colour-keying pure black, so the dark
  parts *inside* the artwork survive:
  ```python
  rgba = src.convert('RGBA')
  lum = src.convert('L')
  rgba.putalpha(lum.point(lambda v: 0 if v < 10 else min(255, int(v * 3))))
  ```
- **Don't flatten with `.convert('RGB')`.** It composites the alpha onto black,
  and the icon arrives with a black tile behind it.
- **Trim on a threshold (`alpha > 8`), not on `getbbox()` alone.** These
  renders carry a faint glow that bleeds nearly to the frame edge, so a plain
  `getbbox()` keeps ~20% of the width as margin and the artwork renders
  shrunken inside its own padding. Don't pad the result to a square either —
  both glyphs are wider than tall, and the padding is dead space in every slot
  that uses them. Ship the natural aspect and let `BoxFit.contain` place it.
