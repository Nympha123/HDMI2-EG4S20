`timescale 1ns/1ps

// FAT32 根目录分区扫描器：只收 A01..A10 / B01..B10 / C01..C10 / D01..D10。
// 输出 4 个分区的图片扇区表（每区最多 10 张）。
// 只扫根目录首簇（FAT32 根目录通常 4KB，足够 40 张图 + LFN）。
module fat32_zone_scan (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         busy,
    output reg         done,
    output reg  [7:0]  fs_error,

    // 分区表读口
    input  wire [1:0]  rd_zone,
    input  wire [3:0]  rd_idx,
    output wire [31:0] rd_sector,
    output wire        rd_valid,
    input  wire [1:0]  rd2_zone,
    input  wire [3:0]  rd2_idx,
    output wire [31:0] rd2_sector,
    output wire [4:0]  zone0_count,
    output wire [4:0]  zone1_count,
    output wire [4:0]  zone2_count,
    output wire [4:0]  zone3_count,

    // SD 扇区请求（接 sd_sector_adapter 的 sector_req）
    output reg         sd_req,
    output reg  [31:0] sd_lba,
    input  wire        sd_busy,
    input  wire        sd_valid,
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,
    input  wire        sd_done,
    input  wire [7:0]  sd_error
);
    localparam [3:0] S_IDLE   = 4'd0,
                     S_BOOT_W = 4'd1,
                     S_BOOT2  = 4'd2,
                     S_ROOT_S = 4'd3,
                     S_ROOT_W = 4'd4,
                     S_ROOT_N = 4'd5,
                     S_DONE   = 4'd6;
    reg [3:0] state;

    // boot 字段
    reg [7:0]  bt_11, bt_12, bt_13, bt_14, bt_15, bt_16, bt_17, bt_18;
    reg [7:0]  bt_36, bt_37, bt_38, bt_39, bt_44, bt_45, bt_46, bt_47;
    reg [7:0]  bt_454, bt_455, bt_456, bt_457;
    reg [31:0] part_lba;
    reg        mbr_tried;
    reg [31:0] fatsz;
    reg [31:0] root_lba;
    reg [31:0] data_lba;
    reg [7:0]  spc;
    reg [7:0]  root_sec_idx;
    reg [7:0]  numfat;
    reg [15:0] reserved;

    // 目录项
    reg [7:0]  nm0, nm1, nm2, nm3;
    reg [7:0]  ext0, ext1, ext2;
    reg        ent_lfn, ent_del, ent_dir;
    reg [31:0] ent_cluster;
    reg [15:0] ent_chi, ent_clo;

    reg [31:0] sec_mem [0:39];
    reg [4:0]  cnt0, cnt1, cnt2, cnt3;
    // v36: 按文件名编号落位(A05 -> 槽 4)，并记录哪些槽位真的有图
    reg [9:0]  pm0, pm1, pm2, pm3;
    assign zone0_count = cnt0;
    assign zone1_count = cnt1;
    assign zone2_count = cnt2;
    assign zone3_count = cnt3;

    wire [31:0] bps    = {16'd0, bt_12, bt_11};
    wire [31:0] fat16  = {16'd0, bt_18, bt_17};
    wire [31:0] fat32  = {bt_39, bt_38, bt_37, bt_36};
    wire [31:0] fatsz_w = (fat16 != 32'd0) ? fat16 : fat32;
    wire [31:0] rootclus = {bt_47, bt_46, bt_45, bt_44};
    wire [31:0] part_w  = {bt_457, bt_456, bt_455, bt_454};

    wire [31:0] meta_base = part_lba + {16'd0, reserved} + ({24'd0, numfat} * fatsz);
    wire [31:0] root_off  = (rootclus - 32'd2) * {24'd0, spc};

    assign rd_valid = (rd_zone == 2'd0) ? (rd_idx < cnt0 && pm0[rd_idx]) :
                      (rd_zone == 2'd1) ? (rd_idx < cnt1 && pm1[rd_idx]) :
                      (rd_zone == 2'd2) ? (rd_idx < cnt2 && pm2[rd_idx]) : (rd_idx < cnt3 && pm3[rd_idx]);
    wire [5:0] rd_addr = {4'd0, rd_zone} * 6'd10 + {2'd0, rd_idx};
    assign rd_sector = sec_mem[rd_addr];
    wire [5:0] rd2_addr = {4'd0, rd2_zone} * 6'd10 + {2'd0, rd2_idx};
    assign rd2_sector = sec_mem[rd2_addr];

    wire [7:0] d0 = nm1, d1 = nm2;
    wire [3:0] dnum = ({4'd0, d0[3:0]} * 4'd10) + {4'd0, d1[3:0]};
    wire [3:0] dnum_slot = dnum - 4'd1;          // 0-based 槽位
    wire name_zone_ok = (nm0 >= "A") && (nm0 <= "D");
    wire digits_ok = (d0 >= "0") && (d0 <= "9") && (d1 >= "0") && (d1 <= "9");
    wire ext_ok = (ext0 == "B") && (ext1 == "M") && (ext2 == "P");
    wire ent_ok = !ent_lfn && !ent_del && !ent_dir && name_zone_ok && digits_ok && ext_ok;
    wire [1:0] ent_zone = nm0 - "A";
    wire [31:0] ent_sector = data_lba + ((({ent_chi, ent_clo}) - 32'd2) * {24'd0, spc});

    // -----------------------------------------------------------------------
    // v79：分区扫描看门狗
    //   分区扫描是 SD 总线上的最高优先级（zscan_active 一来，仲裁就全给它）。
    //   一旦它卡在某笔事务上，整条 SD 总线会被永久占用 —— 图片和音乐全死。
    //   每个扇区 84 ms 的兜底，超时就报错并强制进 S_DONE 释放总线。
    // -----------------------------------------------------------------------
    reg [21:0] wdt;
    wire       wdt_ev = (wdt == 22'h3F_FFFF);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                            wdt <= 22'd0;
        else if (!busy || sd_valid || sd_done) wdt <= 22'd0;
        else if (!wdt_ev)                      wdt <= wdt + 22'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0; fs_error <= 8'd0;
            sd_req <= 1'b0; sd_lba <= 32'd0;
            part_lba <= 32'd0; fatsz <= 32'd0; root_lba <= 32'd0; data_lba <= 32'd0;
            spc <= 8'd0; root_sec_idx <= 8'd0; numfat <= 8'd0; reserved <= 16'd0;
            mbr_tried <= 1'b0;
            ent_lfn <= 1'b0; ent_del <= 1'b0; ent_dir <= 1'b0;
            ent_cluster <= 32'd0; ent_chi <= 16'd0; ent_clo <= 16'd0;
            cnt0 <= 5'd0; cnt1 <= 5'd0; cnt2 <= 5'd0; cnt3 <= 5'd0;
            pm0 <= 10'd0; pm1 <= 10'd0; pm2 <= 10'd0; pm3 <= 10'd0;
        end else begin
            // 目录项字节流解析
            if (state == S_ROOT_W && sd_valid) begin
                if (sd_byte_index[4:0] == 5'd0) begin
                    ent_lfn <= (sd_byte == 8'h0F);
                    ent_del <= (sd_byte == 8'hE5);
                    nm0 <= sd_byte; nm1 <= 0; nm2 <= 0; nm3 <= 0;
                end else if (sd_byte_index[4:0] == 5'd1) nm1 <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd2) nm2 <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd3) nm3 <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd8) ext0 <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd9) ext1 <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd10) ext2 <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd11) ent_dir <= sd_byte[4];
                else if (sd_byte_index[4:0] == 5'd20) ent_chi[7:0] <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd21) ent_chi[15:8] <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd26) ent_clo[7:0] <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd27) ent_clo[15:8] <= sd_byte;
                else if (sd_byte_index[4:0] == 5'd31) begin
                    ent_cluster <= {ent_chi, ent_clo};
                    if (ent_ok && (dnum >= 4'd1) && (dnum <= 4'd10)) begin
                        // v36: 按文件名编号落位，和目录里的先后顺序无关
                        case (ent_zone)
                            2'd0: begin sec_mem[{4'd0, dnum_slot}] <= ent_sector; pm0[dnum_slot] <= 1'b1; if (cnt0 < dnum) cnt0 <= dnum; end
                            2'd1: begin sec_mem[6'd10 + {4'd0, dnum_slot}] <= ent_sector; pm1[dnum_slot] <= 1'b1; if (cnt1 < dnum) cnt1 <= dnum; end
                            2'd2: begin sec_mem[6'd20 + {4'd0, dnum_slot}] <= ent_sector; pm2[dnum_slot] <= 1'b1; if (cnt2 < dnum) cnt2 <= dnum; end
                            default: begin sec_mem[6'd30 + {4'd0, dnum_slot}] <= ent_sector; pm3[dnum_slot] <= 1'b1; if (cnt3 < dnum) cnt3 <= dnum; end
                        endcase
                    end
                end
            end

            // boot 字段
            if (state == S_BOOT_W && sd_valid) begin
                case (sd_byte_index)
                    9'd11: bt_11 <= sd_byte;
                    9'd12: bt_12 <= sd_byte;
                    9'd13: spc <= sd_byte;
                    9'd14: bt_14 <= sd_byte;
                    9'd15: bt_15 <= sd_byte;
                    9'd16: numfat <= sd_byte;
                    9'd17: bt_17 <= sd_byte;
                    9'd18: bt_18 <= sd_byte;
                    9'd36: bt_36 <= sd_byte;
                    9'd37: bt_37 <= sd_byte;
                    9'd38: bt_38 <= sd_byte;
                    9'd39: bt_39 <= sd_byte;
                    9'd44: bt_44 <= sd_byte;
                    9'd45: bt_45 <= sd_byte;
                    9'd46: bt_46 <= sd_byte;
                    9'd47: bt_47 <= sd_byte;
                    9'd454: bt_454 <= sd_byte;
                    9'd455: bt_455 <= sd_byte;
                    9'd456: bt_456 <= sd_byte;
                    9'd457: bt_457 <= sd_byte;
                    default: ;
                endcase
            end

            if (wdt_ev) begin
                // v79：扇区事务超时，强制收尾，释放总线
                fs_error <= 8'h10;
                sd_req   <= 1'b0;
                state    <= S_DONE;
            end else
            case (state)
                S_IDLE: if (start) begin
                    busy <= 1'b1; done <= 1'b0; fs_error <= 8'd0;
                    sd_req <= 1'b1; sd_lba <= 32'd0;
                    state <= S_BOOT_W;
                end
                S_BOOT_W: begin
                    if (sd_error != 8'd0) begin fs_error <= 8'h10; sd_req <= 1'b0; state <= S_DONE; end
                    else if (sd_done) begin
                        sd_req <= 1'b0;
                        // 2026-10-25: 支持 MBR 分区表。
                        // 老代码这里强制 part_lba = 0：只要卡的 LBA0 是 MBR（Windows 分区表
                        // 格式化出来的卡基本都是，FAT32 从 2048 起），就会按错的几何去读根目录，
                        // A01..D10 一张都扫不到 -> 四张分区表全空 -> 进任何展区都还停在开机
                        // 那张图，而且 A/D 也动不了（zone_cur_count = 0）。
                        // 判定：BPB 的 bytes-per-sector 不是 512（MBR 该位置是引导代码）。
                        if ((bps != 32'd512) || (spc == 8'd0)) begin
                            if (mbr_tried) begin
                                fs_error <= 8'h21;
                                state    <= S_DONE;
                            end else begin
                                mbr_tried <= 1'b1;
                                part_lba  <= part_w;
                                sd_req    <= 1'b1;
                                sd_lba    <= part_w;      // 到分区起点重读 BPB
                                state     <= S_BOOT_W;
                            end
                        end else begin
                            fatsz <= (fat16 != 32'd0) ? fat16 : fat32;
                            reserved <= {bt_15, bt_14};
                            numfat <= numfat;
                            state <= S_ROOT_S;
                        end
                    end
                end
                S_ROOT_S: begin
                    root_lba  <= meta_base + root_off;
                    data_lba  <= meta_base;
                    root_sec_idx <= 8'd0;
                    sd_req <= 1'b1;
                    sd_lba <= meta_base + root_off;
                    state <= S_ROOT_W;
                end
                S_ROOT_W: begin
                    if (sd_error != 8'd0) begin fs_error <= 8'h10; sd_req <= 1'b0; state <= S_DONE; end
                    else if (sd_done) begin
                        sd_req <= 1'b0;
                        if (root_sec_idx + 8'd1 >= spc) begin
                            state <= S_DONE;
                        end else begin
                            root_sec_idx <= root_sec_idx + 8'd1;
                            state <= S_ROOT_N;
                        end
                    end
                end
                S_ROOT_N: begin
                    sd_lba <= root_lba + {24'd0, root_sec_idx};
                    sd_req <= 1'b1;
                    state <= S_ROOT_W;
                end
                S_DONE: begin
                    sd_req <= 1'b0;
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
