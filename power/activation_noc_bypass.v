`timescale 1ns/1ps
// activation_noc_bypass.v -- ablation for the power study.
//
// Same ports and the same six scratchpad banks as the mentor's activation_noc.v, but with
// the network taken out: every producer writes its bank directly, the way the baseline
// writes its SRAMs. No ingress registers, no destination field, no round-robin arbiter,
// no 6-to-1 crossbar muxes.
//
// In lenet_noc every source i only ever sends to bank i (net_dest[i] = i), so this is the
// same design minus the NoC logic. Results are bit-identical; each transfer arrives one
// clock earlier because the NoC's ingress register is gone.
//
// Build lenet_noc.v with this file instead of activation_noc.v (module name is the same).
module activation_noc (
    input clk, rstn,
    input [5:0] in_valid,
    output [5:0] in_ready,
    input [5:0][2:0] in_dest,
    input [5:0][9:0] in_addr,
    input [5:0][255:0] in_data,
    input [5:0] read_enable,
    input [5:0][9:0] read_addr,
    output wire [5:0] delivered_valid,
    output wire [5:0][9:0] delivered_addr,
    output wire [5:0][255:0] delivered_data,
    output reg [5:0][255:0] read_data
);
    // synthesis translate_off
`ifdef REPORT_HIERARCHY
    initial $display("HIERARCHY NoC %m");
`endif
    // synthesis translate_on

    wire [5:0] occupied = 6'b0;          // nothing is ever held (kept for the mentor's testbench)
    assign in_ready        = 6'b111111;
    assign delivered_valid = in_valid & {6{rstn}};
    assign delivered_addr  = in_addr;
    assign delivered_data  = in_data;

    genvar b;
    generate for (b=0;b<6;b=b+1) begin: bank
        if (b==0 || b==2) begin: stream_endpoint
            always @(posedge clk) read_data[b] <= 0;
        end else begin: buffered_endpoint
        localparam DEPTH = b==1 ? 256 : b==3 ? 32 : 128;
        localparam WIDTH = b==1 ? 96 : b==3 ? 256 : 16;
        reg [WIDTH-1:0] mem [0:DEPTH-1];
        always @(posedge clk) begin
            if (delivered_valid[b]) mem[delivered_addr[b]] <= delivered_data[b][WIDTH-1:0];
            if (read_enable[b]) read_data[b] <= mem[read_addr[b]];
        end
        end
    end endgenerate
endmodule
