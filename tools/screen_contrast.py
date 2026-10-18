"""실기기 스크린샷에서 글자 대비를 잰다.

    adb exec-out screencap -p > shot.png
    python3 tools/screen_contrast.py shot.png x0,y0,x1,y1 [...]

영역마다 '바탕 / 글자 / 대비' 를 찍는다. 가장 넓은 색을 바탕으로 보고,
12픽셀 이상 나온 색 중 바탕에서 가장 먼 것을 글자로 본다.

**저장된 파일에서 재는 것이 요점이다.** 살아 있는 화면을 따로 두 번
찍으면 그 사이에 게임 상태가 바뀌어, 스크린샷에서 본 것과 다른 것을
재게 된다. 실제로 그렇게 멀쩡한 칩을 1.01:1 로 잘못 읽은 적이 있다.

위젯 단위 대비는 flutter_app/test/theme/rendered_contrast_test.dart 가
자동으로 본다. 이 도구는 거기서 못 그리는 것 — 게임 중 상태, 팝업,
실제 기기에서만 나오는 화면 — 을 눈으로 확인할 때 쓴다.

PIL 없이 PNG 를 직접 푼다(표준 라이브러리만).
"""
import zlib, struct, sys, collections

def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n', 'PNG 이 아니다'
    pos, idat, w = 8, b'', None
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        body = d[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w, h, depth, color = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and color in (2, 6), f'지원 안 함 depth={depth} color={color}'
            ch = 3 if color == 2 else 4
        elif typ == b'IDAT':
            idat += body
        elif typ == b'IEND':
            break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * ch
    out = bytearray(w * h * ch)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(ch, stride): line[i] = (line[i] + line[i-ch]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                c = prev[i-ch] if i >= ch else 0
                b = prev[i]
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y*stride:(y+1)*stride] = line
        prev = line
    return w, h, ch, out

def lum(c):
    g = lambda v: (v/255)/12.92 if v/255 <= 0.03928 else (((v/255)+0.055)/1.055)**2.4
    return 0.2126*g(c[0]) + 0.7152*g(c[1]) + 0.0722*g(c[2])

def ratio(a, b):
    x, y = lum(a), lum(b)
    hi, lo = (x, y) if x > y else (y, x)
    return (hi+0.05)/(lo+0.05)

if __name__ == '__main__':
    path = sys.argv[1]
    w, h, ch, px = read_png(path)
    print(f'# {path.split("/")[-1]}  {w}x{h}')
    for arg in sys.argv[2:]:
        x0, y0, x1, y1 = map(int, arg.split(','))
        c = collections.Counter()
        for y in range(max(0, y0), min(h, y1)):
            for x in range(max(0, x0), min(w, x1)):
                i = (y*w + x)*ch
                c[(px[i], px[i+1], px[i+2])] += 1
        top = c.most_common()
        if not top:
            print(f'{arg}: (빈 영역)'); continue
        bg = top[0][0]
        glyph = max((k for k, n in top if n >= 12), key=lambda k: ratio(k, bg), default=bg)
        print(f'{arg}: 바탕 #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}  '
              f'글자 #{glyph[0]:02X}{glyph[1]:02X}{glyph[2]:02X}  대비 {ratio(glyph, bg):.2f}:1')
