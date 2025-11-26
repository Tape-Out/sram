`ifndef SRAM_MMIO_V
`define SRAM_MMIO_V

`timescale 1ns/1ps

`ifndef SRAM_DEFAULT_SIZE
`define SRAM_DEFAULT_SIZE 4096  // 4kb
`endif

module sram_mmio #(
    parameter [31:0]  BASE_ADDR     = 32'h8100_8000,
    parameter integer MEM_SIZE      = `SRAM_DEFAULT_SIZE
)(
    input  wire                     clk,
    input  wire                     resetn,

    input  wire                     mem_valid,
    input  wire                     mem_instr,
    output reg                      mem_ready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0]              mem_addr,
    input  wire [31:0]              mem_wdata,
    /* verilator lint_on  UNUSEDSIGNAL */
    input  wire [3:0]               mem_wstrb,
    output reg  [31:0]              mem_rdata,

    output reg                      irq,
    input  wire                     eoi
);

    localparam WORD_DEPTH = MEM_SIZE / 4;
    reg [31:0] sram_mem [0:WORD_DEPTH-1];
    reg        addr_oom                 ;

    wire [31:0] local_addr = mem_addr - BASE_ADDR;
    wire addr_valid = ((mem_addr >= BASE_ADDR) && (local_addr < MEM_SIZE) && (local_addr[1:0] == 0));
    wire [31:0] word_addr = local_addr >> 2;

    wire [31:0] wmask = { {8{mem_wstrb[3]}}, {8{mem_wstrb[2]}}, {8{mem_wstrb[1]}}, {8{mem_wstrb[0]}} };
    wire [31:0] wdata = mem_wdata & wmask;

    genvar j;
    generate
        for (j = 0; j < WORD_DEPTH; j = j + 1) begin: FLUSH_SRAM_2_0
            always @(posedge clk) begin
                if (!resetn) begin
                    sram_mem[j] <= 0;
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 0;
        end else mem_ready <= mem_valid && !mem_instr;
    end

    always @(posedge clk) begin
        if (!resetn || eoi) begin
            addr_oom <= 0;
            irq <= 0;
        end else irq <= addr_oom;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            mem_rdata <= 32'b0;
        end else if (mem_valid && !mem_instr) begin
            if (addr_valid) begin
                if (|mem_wstrb) begin: SRAM_WRITE
                    if (word_addr < WORD_DEPTH) begin
                        if (mem_wstrb[0]) sram_mem[word_addr][7:0]   <= mem_wdata[7:0];
                        if (mem_wstrb[1]) sram_mem[word_addr][15:8]  <= mem_wdata[15:8];
                        if (mem_wstrb[2]) sram_mem[word_addr][23:16] <= mem_wdata[23:16];
                        if (mem_wstrb[3]) sram_mem[word_addr][31:24] <= mem_wdata[31:24];
                    end
                    mem_rdata <= 32'b0;
                end else begin: SRAM_READ
                    if (word_addr < WORD_DEPTH) begin
                        mem_rdata <= sram_mem[word_addr];
                    end else begin
                        mem_rdata <= 32'b0;
                    end
                end
            end else begin
                mem_rdata <= 32'b0;
                addr_oom <= 1;
            end
        end else begin
            mem_rdata <= 32'b0;
        end
    end

endmodule

`endif
