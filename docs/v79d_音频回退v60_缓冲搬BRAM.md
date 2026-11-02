# v79d：音频回退到 v60 + 音频缓冲搬进 BRAM（省 546 LUT）

工程：`E:\AnLU_QianSai\HDMI2-EG4S20_New\HDMI2-EG4S20`
器件：EG4S20BG256（HX4S20C）　工具：Anlogic TD 6.2.168116　日期：2026-10-27
基于：v79c

---

## 1 音频为什么"滋滋"变大了

v79 为了把 97% 的 slices 压下来，动过两处音频相关的东西：

| 改动 | v60 原版 | v79 之后 | 后果 |
|---|---|---|---|
| 环形缓冲深度 | 1024 样本（21.3 ms） | 512 样本（10.7 ms） | 稳态水位从 ~760 掉到 ~248，抗 SD/显示抢占的余量只剩 5 ms |
| 读侧起播策略 | **满一个扇区（256 样本）才放**，收尾(WS_END/WS_WAIT)时才允许零散放 | 有 1 个样本就放 | 每次起播/换曲/循环重启都会经历一段"缓冲只有几个样本"的欠载期，输出被截断/插静音 |

两者叠加，听感上就是"呲啦/滋滋"明显变重（本质是样本流被欠载切断，而不是模拟噪声）。

**处理（按用户要求整体回到 v60 的音频实现）**：

1. `ADDR_WIDTH` 9 → **10**（1024×16，21.3 ms，与 v60 一致）；
2. 读侧恢复 v60 的判定：
   ```verilog
   if ((level_rd >= SAMPLES_PER_SECTOR) ||
       (((wstate_sync2 == WS_END) || (wstate_sync2 == WS_WAIT)) && (level_rd != 0)))
       → 取样本；否则补静音（sample_valid 仍然给，ACR 节拍不断）
   ```
   即"先攒够一个扇区再开声，收尾阶段允许把余量放完"；
3. v79 的**安全性保留**（这些不影响音质）：`player_idle` 换曲握手、扇区事务看门狗、
   `restart` 跨时钟域拉宽、SD 子系统自恢复；
4. 音量/增益/ACR/采样节拍一个字没动。

---

## 2 顺手把音频缓冲搬进 BRAM（省 546 LUT）

原来 `buffer` 的读、写都写在带大量无关逻辑的大 `always` 里，TD 推不出 block RAM，
1024×16 被铺成 **LUTRAM，吃掉近 1000 个 LUT**（这也是当初为什么想减半深度）。

改成标准双端口 RAM 写法后 TD 正常推断：

```verilog
// 写口：单时钟、单写使能、地址单独寄存（wr_ptr 当拍会被 +1，必须锁旧地址）
always @(posedge wr_clk) if (buf_we) buffer[buf_waddr] <= buf_din;
// 读口：独立 always、地址 rd_ptr、输出寄存
always @(posedge rd_clk) buf_q <= buffer[rd_ptr];
```

- 写地址必须**另存一拍**（`buf_waddr <= wr_ptr`），否则会在 `wr_ptr+1` 上写，样本整体错一位；
- 读侧用 `buf_q`：`rd_ptr` 只在 48 kHz 节拍上变，节拍那拍 `buf_q` 正好是 `buffer[rd_ptr]`；
- 结果：`#RAMs 59 → 61`（1024×16 = 2 块 BRAM9K），`#luts 8683 → 8137`（**−546**）。

---

## 3 关掉任意分辨率时 `bmp_read` 的死代码

`hdr_any_size = 1'b0` 时 `pad_rows` 恒为 0，但 `ST_PADTOP` 里的 12 bit 减法循环
（`dv_rem/dv_q` + `pad_rows` 计数器）还在综合网表里。改为：

```verilog
state <= hdr_any_size ? ST_PADTOP : ST_LOAD_DATA;
```

常量折叠后整段 `ST_PADTOP` 变成不可达，被裁掉（约 −100~150 LUT）。
以后要打开任意分辨率，把 `hdr_any_size` 改回 `1'b1` 这条路自动恢复。

---

## 4 结果

| 项 | v79c | **v79d** |
|---|---|---|
| mslices / 4900 | 4537（92.60%） | **4182（85.34%）** |
| 综合 LUT / REG | 8683 / 6462 | **8137 / 6471** |
| BRAM9K / DSP | 59 / 20 | **61 / 20** |
| Setup WNS / TNS | +1117 ps / 0 | **+488 ps / 0** |
| Hold WNS / TNS | +33 ps / 0 | **+21 ps / 0** |
| place seed | 5 | 5 |

- 逻辑片少了 **692**（−7.3 个百分点），代价是 2 块 BRAM（61/64，仍余 3 块）；
- 时序仍全正、0 违例；Hold 余量 21 ps 偏薄，但 `fix_hold` 已开、0 违例。
- bit：`bitstream/HDMI2_HDMI14_Player_v79d.bit`（675,020 B，
  MD5 `27B642E7ABAE56FA92BD53E84E19231B`，
  SHA-256 `55077F4B2AC8BFBE480D3E0EBAAA44BC04DAE2249BF6DFF034BD7E46586D281B`），
  已 `program_spi` 固化。

### 还能省的（本轮没做，供选择）

| 项 | 预估 | 风险 |
|---|---|---|
| `u_shared_font` 与 `u_set_font` 是同一份 font_rom 的两个实例（各 8 BRAM） | −8 BRAM | 需要真双端口 BRAM 同时读两个地址，菜单+设置同屏时依赖它 |
| `fat32_zone_scan.sec_mem` 40×32 → 40×21 | −~70 LUT | 卡容量 >2 TB 才会溢出，实际无影响 |
| 展区徽标 ROM 2bpp → 1bpp | −4 BRAM | 徽标会失去两级色调 |
| `promax_audio_waveform`（313 LUT） | −313 LUT | 要去掉"音频波形"这个扩展项，不建议 |

---

## 5 上板验证

| # | 项 | 期望 |
|---|---|---|
| 1 | 音乐"滋滋" | 应回到 v60/v71 时的水平（比 v79b/v79c 明显轻） |
| 2 | 起播 | 每次起播/换曲会有 ~5 ms 的静音（攒满一个扇区），之后连续 |
| 3 | 循环/换区 | 播完循环、A/B/C/D 换曲正常，不静音、不卡死 |
| 4 | 音量 25/50/100% | 与之前一致 |
| 5 | 图像/UI | 与 v79c 一致（白线、展区名、目录简介都不受影响） |
