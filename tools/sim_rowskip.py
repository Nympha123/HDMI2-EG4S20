# -*- coding: utf-8 -*-
def simulate(W, H, N):
    row_bytes=W*3; row_step=N*W*3; pixel_offset=54; file_len=pixel_offset+W*H*3
    bmp_len=0; skip_until=pixel_offset; row_stop=pixel_offset+row_bytes
    px_cnt=0; hph=0; byte_idx=0; next_row_off=pixel_offset; jump_pending=False
    emitted=[]; cur_addr=0; guard=0
    while True:
        guard+=1
        if guard>2_000_000: raise SystemExit("loop")
        base=cur_addr*512
        for i in range(512):
            valid=(bmp_len>=pixel_offset) and (bmp_len>=skip_until) and (bmp_len<row_stop) and (bmp_len<file_len)
            if valid:
                if byte_idx==2:
                    if hph==0: emitted.append((px_cnt,))     # 该行内第 px_cnt 个像素
                    hph = 0 if (hph+1==N) else hph+1
                    if px_cnt+1>=W:
                        px_cnt=0; jump_pending=(N!=1); next_row_off=next_row_off+row_step
                        if N==1: row_stop=next_row_off+row_step+row_bytes
                        else:    row_stop=0 if (next_row_off+row_step)>=file_len else next_row_off
                    else: px_cnt+=1
                byte_idx = 0 if byte_idx==2 else byte_idx+1
            bmp_len+=1
        if bmp_len>=file_len: break
        jt=(next_row_off>>9)
        if jump_pending and jt>cur_addr:
            cur_addr=jt; skip_until=next_row_off; row_stop=next_row_off+row_bytes
            jump_pending=False; bmp_len=(next_row_off>>9)<<9
        else: cur_addr+=1
    return len(emitted)
for N in (1,2,3):
    for (W,H) in ((640,480),):
        n=simulate(W*N,H*N,N)
        print("N=%d emitted=%d expected=%d %s" % (N,n,W*H,"OK" if n==W*H else "MISMATCH"))
