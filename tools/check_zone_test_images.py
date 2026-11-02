from pathlib import Path
from PIL import Image
import struct

p = Path('tools/test_images_zones')
for name in ['A01.BMP', 'B04.BMP', 'D04.BMP']:
    b = (p / name).read_bytes()
    sig = b[:2]
    size = struct.unpack_from('<I', b, 2)[0]
    off = struct.unpack_from('<I', b, 10)[0]
    hs = struct.unpack_from('<I', b, 14)[0]
    w, h = struct.unpack_from('<ii', b, 18)
    planes, bpp = struct.unpack_from('<HH', b, 26)
    comp = struct.unpack_from('<I', b, 30)[0]
    im = Image.open(p / name)
    print(name, sig, 'file_size', size, 'offset', off, 'header', hs,
          'wxh', w, h, 'bpp', bpp, 'comp', comp, 'mode', im.mode, 'size', im.size)
print('count', len(list(p.glob('*.BMP'))),
      'total_MB', sum(x.stat().st_size for x in p.glob('*.BMP')) / 1e6)
