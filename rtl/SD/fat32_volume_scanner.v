`timescale 1ns/1ps

module fat32_volume_scanner (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    input  wire [1:0]  zone_sel,       // A-D zone letter; 0 = A (legacy PIC still accepted)
    input  wire [8:0]  zone_raddr,     // zone table read address (from sd_card_bmp)
    output wire [63:0] zone_rdata,     // zone table {cluster, size}
    output reg  [4:0]  zone_count,     // number of zone entries found
    output wire        scan_busy,
    output reg         scan_done,
    output reg  [7:0]  fs_error,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [3:0]  resource_valid,
    output reg  [31:0] resource0_cluster,
    output reg  [31:0] resource1_cluster,
    output reg  [31:0] resource2_cluster,
    output reg  [31:0] resource3_cluster,
    output reg  [31:0] resource0_size,
    output reg  [31:0] resource1_size,
    output reg  [31:0] resource2_size,
    output reg  [31:0] resource3_size,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

    localparam ERR_NONE            = 8'h00;
    localparam ERR_SECTOR          = 8'h10;
    localparam ERR_BOOT_SIGNATURE  = 8'h20;
    localparam ERR_UNSUPPORTED_BPB = 8'h21;
    localparam ERR_RESOURCE_MISSING= 8'h22;

    localparam ST_IDLE       = 4'd0;
    localparam ST_READ0_REQ  = 4'd1;
    localparam ST_READ0_WAIT = 4'd2;
    localparam ST_BOOT_PARSE = 4'd3;
    localparam ST_BOOT_REQ   = 4'd4;
    localparam ST_BOOT_WAIT  = 4'd5;
    localparam ST_ROOT_REQ   = 4'd6;
    localparam ST_ROOT_WAIT  = 4'd7;
    localparam ST_DIR_SCAN   = 4'd8;
    localparam ST_FINISH     = 4'd9;
    localparam ST_BOOT_LAYOUT= 4'd10;
    localparam ST_BOOT_ROOT  = 4'd11;
    // 读卡兼容（讲义外补丁）：FAT32 的根目录是一个普通簇链（可以跨多个簇），
    // 讲义版只扫根目录第一个簇，根目录涨到多簇后就找不到图片，需要跟随簇链。
    localparam ST_ROOT_FAT_REQ   = 4'd12;
    localparam ST_ROOT_FAT_WAIT  = 4'd13;
    localparam ST_ROOT_FAT_PARSE = 4'd14;
    // 第八讲 S4b：根目录簇 → LBA 的流水线中间拍（只做一次 32 位加法，见下方注释）
    localparam ST_ROOT_LBA_ADD   = 4'd15;

    reg [3:0] state;
    // Boot-sector bytes are captured as they stream in; the full 512-byte
    // buffer is no longer needed (it used to be a 1078-LUT4 / 1127-reg
    // distributed RAM block). Root-directory matching already streams bytes
    // into dir_name0..10.
    reg [7:0] bt_0, bt_11, bt_12, bt_13, bt_14, bt_15, bt_16, bt_17, bt_18;
    reg [7:0] bt_22, bt_23, bt_32, bt_33, bt_34, bt_35;
    reg [7:0] bt_36, bt_37, bt_38, bt_39, bt_44, bt_45, bt_46, bt_47;
    reg [7:0] bt_450, bt_454, bt_455, bt_456, bt_457, bt_510, bt_511;
    wire [15:0] bt_bps          = {bt_12, bt_11};
    wire [15:0] bt_reserved      = {bt_15, bt_14};
    wire [15:0] bt_root_entries  = {bt_18, bt_17};
    wire [15:0] bt_fat16         = {bt_23, bt_22};
    wire [31:0] bt_total         = {bt_35, bt_34, bt_33, bt_32};
    wire [31:0] bt_fat32         = {bt_39, bt_38, bt_37, bt_36};
    wire [31:0] bt_root_cluster  = {bt_47, bt_46, bt_45, bt_44};
    wire [31:0] bt_part_lba      = {bt_457, bt_456, bt_455, bt_454};
    reg [4:0] directory_entry_index;
    reg [31:0] root_cluster;
    reg [31:0] total_sectors;
    reg [31:0] fat_sectors;
    reg [7:0] fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] root_lba;
    // 第八讲 S4b：把“根目录簇 → LBA”拆成两拍，缓解 sd_card_clk(100MHz) 域时序
    //   第 1 拍：root_offset <= (cluster - 2) << sectors_per_cluster_shift
    //   第 2 拍（ST_ROOT_LBA_ADD）：root_lba / sector_lba <= data_start_lba + root_offset
    // 原实现（减法 + 移位 + 32 位加法同拍）是流水线前最差路径的来源。
    // 仅延迟一拍，不改变数值。
    reg [31:0] root_offset;
    reg [7:0] root_sector_index;
    reg [31:0] data_sector_count;
    reg [31:0] fat_span;
    reg [2:0] sectors_per_cluster_shift;
    reg [7:0] dir_name0;
    reg [7:0] dir_name1;
    reg [7:0] dir_name2;
    reg [7:0] dir_name3;
    reg [7:0] dir_name4;
    reg [7:0] dir_name5;
    reg [7:0] dir_name6;
    reg [7:0] dir_name7;
    reg [7:0] dir_name8;
    reg [7:0] dir_name9;
    reg [7:0] dir_name10;
    reg       dir_entry_match;
    reg [1:0] dir_resource_index;
    reg [15:0] dir_cluster_high;
    reg [15:0] dir_cluster_low;
    reg [31:0] dir_file_size;
    // 根目录簇链遍历用
    reg [31:0] root_cluster_cur;      // 当前正在扫描的根目录簇
    reg [4:0]  root_cluster_visits;   // 已扫描的根目录簇数（防死循环）
    reg [8:0]  fat_entry_offset;      // 当前簇的 FAT 表项在本扇区内的字节偏移
    reg [7:0]  fat_b0;
    reg [7:0]  fat_b1;
    reg [7:0]  fat_b2;
    reg [7:0]  fat_b3;

    wire [27:0] next_root_cluster = {4'd0, fat_b3[3:0], fat_b2, fat_b1, fat_b0};

    assign scan_busy = (state != ST_IDLE);

    // Capture only the boot-sector fields that ST_READ0_WAIT / ST_BOOT_PARSE
    // consume. The stream is byte-validated by the sector reader, so the
    // fields are stable by the time sector_done is seen.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bt_0 <= 8'd0; bt_11 <= 8'd0; bt_12 <= 8'd0; bt_13 <= 8'd0;
            bt_14 <= 8'd0; bt_15 <= 8'd0; bt_16 <= 8'd0; bt_17 <= 8'd0;
            bt_18 <= 8'd0; bt_22 <= 8'd0; bt_23 <= 8'd0; bt_32 <= 8'd0;
            bt_33 <= 8'd0; bt_34 <= 8'd0; bt_35 <= 8'd0; bt_36 <= 8'd0;
            bt_37 <= 8'd0; bt_38 <= 8'd0; bt_39 <= 8'd0; bt_44 <= 8'd0;
            bt_45 <= 8'd0; bt_46 <= 8'd0; bt_47 <= 8'd0; bt_450 <= 8'd0;
            bt_454 <= 8'd0; bt_455 <= 8'd0; bt_456 <= 8'd0; bt_457 <= 8'd0;
            bt_510 <= 8'd0; bt_511 <= 8'd0;
        end else if (sector_valid &&
                     ((state == ST_READ0_WAIT) || (state == ST_BOOT_WAIT))) begin
            case (sector_byte_index)
                9'd0:   bt_0   <= sector_byte;
                9'd11:  bt_11  <= sector_byte;
                9'd12:  bt_12  <= sector_byte;
                9'd13:  bt_13  <= sector_byte;
                9'd14:  bt_14  <= sector_byte;
                9'd15:  bt_15  <= sector_byte;
                9'd16:  bt_16  <= sector_byte;
                9'd17:  bt_17  <= sector_byte;
                9'd18:  bt_18  <= sector_byte;
                9'd22:  bt_22  <= sector_byte;
                9'd23:  bt_23  <= sector_byte;
                9'd32:  bt_32  <= sector_byte;
                9'd33:  bt_33  <= sector_byte;
                9'd34:  bt_34  <= sector_byte;
                9'd35:  bt_35  <= sector_byte;
                9'd36:  bt_36  <= sector_byte;
                9'd37:  bt_37  <= sector_byte;
                9'd38:  bt_38  <= sector_byte;
                9'd39:  bt_39  <= sector_byte;
                9'd44:  bt_44  <= sector_byte;
                9'd45:  bt_45  <= sector_byte;
                9'd46:  bt_46  <= sector_byte;
                9'd47:  bt_47  <= sector_byte;
                9'd450: bt_450 <= sector_byte;
                9'd454: bt_454 <= sector_byte;
                9'd455: bt_455 <= sector_byte;
                9'd456: bt_456 <= sector_byte;
                9'd457: bt_457 <= sector_byte;
                9'd510: bt_510 <= sector_byte;
                9'd511: bt_511 <= sector_byte;
                default: ;
            endcase
        end
    end

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = value != 0 && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    // 读卡兼容（讲义外补丁）：把小写 ASCII 字母转成大写，用于 8.3 文件名比较。
    // 原因：Windows 对“本来就合法 8.3”的文件名按用户输入原样写盘，
    // 因此输入 PIC1.bmp 时磁盘上的短名就是 "PIC1    bmp"（小写扩展名），
    // 讲义版扫描器只接受大写 BMP，会误判为“找不到图片”。
    function [7:0] upcase;
        input [7:0] c;
        begin
            if (c >= 8'h61 && c <= 8'h7A)
                upcase = c - 8'h20;
            else
                upcase = c;
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    // Zone name A01..A10 (2-digit index); the legacy PIC1..PIC4 names stay
    // accepted for zone A only.
    wire [7:0] dir_zone_letter = 8'h41 + {6'b0, zone_sel};
    wire [7:0] dir_zone_d1     = upcase(dir_name1) - "0";
    wire [7:0] dir_zone_d2     = upcase(dir_name2) - "0";
    wire [7:0] dir_zone_num    = (dir_zone_d1 << 3) + (dir_zone_d1 << 1) + dir_zone_d2;
    wire dir_pic_ok  = (zone_sel == 2'd0) &&
                       (upcase(dir_name0) == "P") && (upcase(dir_name1) == "I") &&
                       (upcase(dir_name2) == "C") &&
                       (upcase(dir_name3) >= "1") && (upcase(dir_name3) <= "4");
    wire dir_zone_ok = (upcase(dir_name0) == dir_zone_letter) &&
                       (upcase(dir_name1) >= "0") && (upcase(dir_name1) <= "9") &&
                       (upcase(dir_name2) >= "0") && (upcase(dir_name2) <= "9") &&
                       (dir_zone_num >= 8'd1) && (dir_zone_num <= 8'd10) &&
                       (dir_name3 == " ");

    // 512x64 zone table (cluster + size); only the first 10 entries are used.
    reg        zone_we;
    reg [8:0]  zone_waddr;
    reg [63:0] zone_wdata;
    reg [3:0]  dir_zone_index;
    wire [63:0] zone_rdata_w;
    zone_table u_zone_table (
        .clk   (clk),
        .we    (zone_we),
        .waddr (zone_waddr),
        .wdata (zone_wdata),
        .raddr (zone_raddr),
        .rdata (zone_rdata_w)
    );
    assign zone_rdata = zone_rdata_w;

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            scan_done <= 1'b0;
            fs_error <= ERR_NONE;
            partition_lba <= 32'd0;
            sectors_per_cluster <= 8'd0;
            fat_start_lba <= 32'd0;
            data_start_lba <= 32'd0;
            max_cluster <= 32'd0;
            resource_valid <= 4'd0;
            resource0_cluster <= 32'd0;
            resource1_cluster <= 32'd0;
            resource2_cluster <= 32'd0;
            resource3_cluster <= 32'd0;
            resource0_size <= 32'd0;
            resource1_size <= 32'd0;
            resource2_size <= 32'd0;
            resource3_size <= 32'd0;
            zone_count <= 5'd0;
            zone_we <= 1'b0;
            zone_waddr <= 9'd0;
            zone_wdata <= 64'd0;
            dir_zone_index <= 4'd0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            directory_entry_index <= 5'd0;
            root_cluster <= 32'd0;
            total_sectors <= 32'd0;
            fat_sectors <= 32'd0;
            fat_count <= 8'd0;
            reserved_sectors <= 16'd0;
            root_lba <= 32'd0;
            root_offset <= 32'd0;
            root_sector_index <= 8'd0;
            data_sector_count <= 32'd0;
            fat_span <= 32'd0;
            sectors_per_cluster_shift <= 3'd0;
            dir_name0 <= 8'd0;
            dir_name1 <= 8'd0;
            dir_name2 <= 8'd0;
            dir_name3 <= 8'd0;
            dir_name4 <= 8'd0;
            dir_name5 <= 8'd0;
            dir_name6 <= 8'd0;
            dir_name7 <= 8'd0;
            dir_name8 <= 8'd0;
            dir_name9 <= 8'd0;
            dir_name10 <= 8'd0;
            dir_entry_match <= 1'b0;
            dir_resource_index <= 2'd3;
            dir_cluster_high <= 16'd0;
            dir_cluster_low <= 16'd0;
            dir_file_size <= 32'd0;
            root_cluster_cur <= 32'd0;
            root_cluster_visits <= 5'd0;
            fat_entry_offset <= 9'd0;
            fat_b0 <= 8'd0;
            fat_b1 <= 8'd0;
            fat_b2 <= 8'd0;
            fat_b3 <= 8'd0;
        end else begin
            scan_done <= 1'b0;
            sector_req <= 1'b0;
            zone_we <= 1'b0;

            if (sector_valid && state == ST_ROOT_WAIT) begin
                case (sector_byte_index[4:0])
                    5'd0: begin
                        dir_name0 <= sector_byte;
                        dir_entry_match <= 1'b0;
                    end
                    5'd1:  dir_name1 <= sector_byte;
                    5'd2:  dir_name2 <= sector_byte;
                    5'd3:  dir_name3 <= sector_byte;
                    5'd4:  dir_name4 <= sector_byte;
                    5'd5:  dir_name5 <= sector_byte;
                    5'd6:  dir_name6 <= sector_byte;
                    5'd7:  dir_name7 <= sector_byte;
                    5'd8:  dir_name8 <= sector_byte;
                    5'd9:  dir_name9 <= sector_byte;
                    5'd10: dir_name10 <= sector_byte;
                    5'd11: begin
                        // 读卡兼容：8.3 名比较改为大小写不敏感（见 upcase 说明）
                        if (sector_byte == 8'h20 &&
                            (dir_pic_ok || dir_zone_ok) &&
                            dir_name4 == " " &&
                            dir_name5 == " " && dir_name6 == " " &&
                            dir_name7 == " " && upcase(dir_name8) == "B" &&
                            upcase(dir_name9) == "M" && upcase(dir_name10) == "P") begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= dir_pic_ok
                                ? (upcase(dir_name3) - "1")
                                : (dir_zone_num - 8'd1);
                            dir_zone_index <= dir_pic_ok
                                ? (upcase(dir_name3) - "1")
                                : (dir_zone_num - 8'd1);
                        end
                    end
                    5'd20: dir_cluster_high[7:0] <= sector_byte;
                    5'd21: dir_cluster_high[15:8] <= sector_byte;
                    5'd26: dir_cluster_low[7:0] <= sector_byte;
                    5'd27: dir_cluster_low[15:8] <= sector_byte;
                    5'd28: dir_file_size[7:0] <= sector_byte;
                    5'd29: dir_file_size[15:8] <= sector_byte;
                    5'd30: dir_file_size[23:16] <= sector_byte;
                    5'd31: begin
                        dir_file_size[31:24] <= sector_byte;
                        if (dir_entry_match) begin
                            zone_we    <= 1'b1;
                            zone_waddr <= {5'b0, dir_zone_index};
                            zone_wdata <= {dir_cluster_high, dir_cluster_low,
                                           sector_byte, dir_file_size[23:0]};
                            if (zone_count < ({1'b0, dir_zone_index} + 5'd1))
                                zone_count <= {1'b0, dir_zone_index} + 5'd1;
                            case (dir_resource_index)
                                2'd0: begin
                                    resource0_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource0_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[0] <= 1'b1;
                                end
                                2'd1: begin
                                    resource1_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource1_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[1] <= 1'b1;
                                end
                                2'd2: begin
                                    resource2_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource2_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[2] <= 1'b1;
                                end
                                default: begin
                                    resource3_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource3_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[3] <= 1'b1;
                                end
                            endcase
                        end
                    end
                    default: begin end
                endcase
            end

            // 读取根目录簇链的 FAT 表项（每簇 4 字节）
            if (sector_valid && state == ST_ROOT_FAT_WAIT) begin
                if (sector_byte_index == fat_entry_offset)
                    fat_b0 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 1'b1)
                    fat_b1 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd2)
                    fat_b2 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd3)
                    fat_b3 <= sector_byte;
            end

            case (state)
                ST_IDLE: if (scan_start) begin
                    fs_error <= ERR_NONE;
                    partition_lba <= 32'd0;
                    resource_valid <= 4'd0;
                    zone_count <= 5'd0;
                    zone_we <= 1'b0;
                    state <= ST_READ0_REQ;
                end
                ST_READ0_REQ: if (!sector_busy) begin
                    sector_lba <= 32'd0;
                    sector_req <= 1'b1;
                    state <= ST_READ0_WAIT;
                end
                ST_READ0_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (bt_510 != 8'h55 || bt_511 != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else if (bt_0 == 8'heb || bt_0 == 8'he9) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
                    // Some cards/readers expose a FAT32 volume with legacy
                    // partition type 0x04. Keep the reference 0x0B/0x0C
                    // cases and accept 0x04 for the known board medium.
                    end else if (bt_450 == 8'h04 ||
                                 bt_450 == 8'h0b ||
                                 bt_450 == 8'h0c) begin
                        partition_lba <= bt_part_lba;
                        sector_lba <= bt_part_lba;
                        state <= ST_BOOT_REQ;
                    end else begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end
                end
                ST_BOOT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_BOOT_WAIT;
                end
                ST_BOOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (bt_510 != 8'h55 || bt_511 != 8'haa)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else
                        state <= ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE: begin
                    if (bt_bps != 16'd512 || !valid_spc(bt_13) ||
                        bt_reserved == 0 || (bt_16 != 1 && bt_16 != 2) ||
                        bt_root_entries != 0 || bt_fat16 != 0 || bt_total == 0 ||
                        bt_fat32 == 0 || bt_root_cluster < 2) begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end else begin
                        sectors_per_cluster <= bt_13;
                        reserved_sectors <= bt_reserved;
                        fat_count <= bt_16;
                        total_sectors <= bt_total;
                        fat_sectors <= bt_fat32;
                        root_cluster <= bt_root_cluster;
                        sectors_per_cluster_shift <= spc_shift(bt_13);
                        fat_span <= bt_16 == 2 ? (bt_fat32 << 1) : bt_fat32;
                        fat_start_lba <= partition_lba + bt_reserved;
                        state <= ST_BOOT_LAYOUT;
                    end
                end
                ST_BOOT_LAYOUT: begin
                    data_start_lba <= partition_lba + reserved_sectors + fat_span;
                    data_sector_count <= total_sectors - reserved_sectors - fat_span;
                    state <= ST_BOOT_ROOT;
                end
                ST_BOOT_ROOT: begin
                    max_cluster <= (data_sector_count >> sectors_per_cluster_shift) + 1'b1;
                    // 第 1 拍：只算偏移（减法 + 寄存器化移位量的移位）
                    root_offset <= (root_cluster - 32'd2) << sectors_per_cluster_shift;
                    root_sector_index <= 8'd0;
                    resource_valid <= 4'd0;
                    root_cluster_cur <= root_cluster;
                    root_cluster_visits <= 5'd0;
                    state <= ST_ROOT_LBA_ADD;
                end
                // 第 2 拍：只做一次 32 位加法，得到根目录首扇区 LBA
                ST_ROOT_LBA_ADD: begin
                    root_lba   <= data_start_lba + root_offset;
                    sector_lba <= data_start_lba + root_offset;
                    state <= ST_ROOT_REQ;
                end
                ST_ROOT_REQ: if (!sector_busy) begin
                    dir_entry_match <= 1'b0;
                    sector_req <= 1'b1;
                    state <= ST_ROOT_WAIT;
                end
                ST_ROOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else begin
                        directory_entry_index <= 5'd0;
                        state <= ST_DIR_SCAN;
                    end
                end
                ST_DIR_SCAN: begin
                    if (root_sector_index + 1'b1 < sectors_per_cluster) begin
                        root_sector_index <= root_sector_index + 1'b1;
                        sector_lba <= root_lba + root_sector_index + 1'b1;
                        state <= ST_ROOT_REQ;
                    end else begin
                        // 本簇扫完：按 FAT 链读下一个根目录簇，直到整棵根目录扫完
                        // （最多 10 个展区条目，不能在前 4 项就提前结束）。
                        fat_entry_offset <= {root_cluster_cur[6:0], 2'b00};
                        sector_lba <= fat_start_lba + (root_cluster_cur >> 7);
                        state <= ST_ROOT_FAT_REQ;
                    end
                end
                ST_ROOT_FAT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_ROOT_FAT_WAIT;
                end
                ST_ROOT_FAT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else
                        state <= ST_ROOT_FAT_PARSE;
                end
                ST_ROOT_FAT_PARSE: begin
                    if (next_root_cluster >= 28'hffffff8) begin
                        // 根目录簇链结束：只要扫到至少一个展区条目就算成功
                        if (zone_count != 5'd0)
                            state <= ST_FINISH;
                        else
                            finish_with_error(ERR_RESOURCE_MISSING);
                    end else if (next_root_cluster < 28'd2 ||
                                 next_root_cluster > max_cluster) begin
                        // FAT 链异常
                        finish_with_error(ERR_SECTOR);
                    end else if (root_cluster_visits >= 5'd15) begin
                        if (zone_count != 5'd0)
                            state <= ST_FINISH;
                        else
                            finish_with_error(ERR_RESOURCE_MISSING);
                    end else begin
                        root_cluster_cur <= {4'd0, next_root_cluster};
                        root_cluster_visits <= root_cluster_visits + 5'd1;
                        // 第 1 拍：只算偏移，加法放到 ST_ROOT_LBA_ADD
                        root_offset <= ({4'd0, next_root_cluster} - 32'd2)
                                       << sectors_per_cluster_shift;
                        root_sector_index <= 8'd0;
                        state <= ST_ROOT_LBA_ADD;
                    end
                end
                ST_FINISH: begin
                    scan_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

// 512 x 64 zone table: {cluster, size}. Only the first 10 entries are used,
// but the depth is chosen so the synthesizer infers a BRAM instead of a
// large LUTRAM/register block.
module zone_table (
    input  wire        clk,
    input  wire        we,
    input  wire [8:0]  waddr,
    input  wire [63:0] wdata,
    input  wire [8:0]  raddr,
    output reg  [63:0] rdata
);
    reg [63:0] mem [0:511];
    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule
