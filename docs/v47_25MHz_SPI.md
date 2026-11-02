# v47 SPI 高速段 25 MHz（当前定版）

日期：2026-10-26

## 1. 背景

v45 的 SD 读是 SPI **12.5 MHz**（50 MHz / 4）+ 每 512 B 一个 CMD17。
A05/A06 3.9/5.8 s，普通 640×480 按键后约 1 s 才开始。

v46 尝试 CMD18 多块读 + 8 扇区缓存，上板后图片/音乐全无，已回退。
v47 改用风险更小的方案：**不改 SD 命令/读状态机，只把 SPI 高速段提到 25 MHz**。

## 2. 改法

`rtl/SD/spi_master.v` 增加 `S_FAST` 状态：

- `clk_div == 0`（初始化完成后 `SPI_HIGH_SPEED_DIV=0`）时，IDLE 收到
  `wr_req` 直接进入 `S_FAST`，DCLK **每拍翻转一次**，16 拍发完一个字节；
- `clk_div != 0`（初始化 248）仍走原来的 `DCLK_IDLE/DCLK_EDGE` 四拍节奏，
  初始化时序完全不变；
- MOSI/MISO 的移位条件仍按 `CPHA/CPOL`，只是把 `S_FAST` 当成
  `DCLK_EDGE` 处理；
- `ACK/ACK_WAIT` 不变，`spi_wr_ack` 仍是一拍。

结果：高速段 SPI 12.5 → **25 MHz**，所有读图/读 WAV 的数据传输时间减半；
CMD17 命令数、SD 初始化、读图链和 v45 完全一致。

## 3. 板测

- 只装 SRAM 测试：图片和音乐**正常**；
- 随后写入配置 FLASH（program_spi + verify/program 通过）；
- 需要用户复测 A05/A06 的实际秒数；理论上数据时间减半，命令延迟不变，
  整体大约快 1.3–1.8×。

## 4. 资源 / 时序

| 项 | v45 | **v47** |
|---|---|---|
| LUT / REG | 17 264 / 6 337 | **17 288 / 6 375** |
| BRAM / DSP | 54 / 20 | **54 / 20** |
| mslices | 4 574 / 4 900 | **4 582 / 4 900（93.5%）** |
| Setup / Hold | +521 / +25 ps | **+1079 / +25 ps**（0 FEPS） |
| bit / MD5 | `…_v45.bit` / `A4270695…` | **`…_v47.bit` / `7330B46F…`** |

## 5. 回退

v45 bit 仍在 `bitstream/HDMI2_HDMI14_Player_v45.bit`，
`project/dsh_flash_v45_rollback.tcl` 可一键写回（12.5 MHz 版）。
