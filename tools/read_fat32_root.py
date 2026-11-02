import struct

path = r"\\.\E:"
with open(path, "rb") as f:
    boot = f.read(512)
    bps = struct.unpack_from('<H', boot, 11)[0]
    spc = boot[13]
    rsv = struct.unpack_from('<H', boot, 14)[0]
    nfat = boot[16]
    fatsz = struct.unpack_from('<I', boot, 36)[0]
    rootclus = struct.unpack_from('<I', boot, 44)[0]
    print('bps', bps, 'spc', spc, 'rsv', rsv, 'nfat', nfat,
          'fatsz', fatsz, 'rootclus', rootclus)
    data_start = rsv + nfat * fatsz
    root_lba = data_start + (rootclus - 2) * spc
    print('data_start', data_start, 'root_lba', root_lba)
    f.seek(root_lba * bps)
    sec = f.read(bps * spc)
    for i in range(0, len(sec) // 32):
        e = sec[i*32:(i+1)*32]
        if e[0] == 0:
            break
        attr = e[11]
        name = e[0:11]
        clus = (struct.unpack_from('<H', e, 20)[0] << 16) | struct.unpack_from('<H', e, 26)[0]
        size = struct.unpack_from('<I', e, 28)[0]
        print(i, name, 'attr=%02x' % attr, 'clus=%d' % clus, 'size=%d' % size)
