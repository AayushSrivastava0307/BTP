`timescale 1ns/1ps
// Single-hop, six-port crossbar NoC with registered ingress flits and
// round-robin destination arbitration. A flit carries dest, address and payload.
// Local scratchpads remain necessary for convolution-window reuse.
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

    reg [5:0] occupied;
    reg [5:0][2:0] dest;
    reg [5:0][9:0] addr;
    reg [5:0][255:0] payload;
    reg [2:0] priority_port [0:5];
    reg [5:0] take;
    integer winner [0:5];
    integer d,k,p;
    always @* begin
        take=0;
        for (d=0; d<6; d=d+1) begin
            winner[d]=-1;
            for (k=0; k<6; k=k+1) begin
                p=(int'(priority_port[d])+k)%6;
                if (winner[d]<0 && occupied[p] && dest[p]==d) begin
                    winner[d]=p;
                    take[p]=1;
                end
            end
        end
    end
    assign in_ready = ~occupied | take;
    integer i;
    always @(posedge clk) begin
        if (!rstn) begin
            occupied<=0;
            for (i=0;i<6;i=i+1) priority_port[i]<=0;
        end else begin
            for (i=0;i<6;i=i+1) begin
                if (take[i]) occupied[i]<=0;
                if (in_valid[i] && in_ready[i]) begin
                    // synthesis translate_off
                    if(in_dest[i]>5) $fatal(1,"Invalid NoC destination");
                    // synthesis translate_on
                    occupied[i]<=1;
                    dest[i]<=in_dest[i];
                    addr[i]<=in_addr[i];
                    payload[i]<=in_data[i];
                end
                if (winner[i]>=0) priority_port[i] <= (winner[i]+1)%6;
            end
        end
    end
    genvar b;
    generate for (b=0;b<6;b=b+1) begin: bank
        assign delivered_valid[b] = rstn && winner[b]>=0;
        assign delivered_addr[b] = winner[b]>=0 ? addr[winner[b]] : 10'd0;
        assign delivered_data[b] = winner[b]>=0 ? payload[winner[b]] : 256'd0;
        if (b==0 || b==2) begin: stream_endpoint
            always @(posedge clk) read_data[b] <= 0;
        end else begin: buffered_endpoint
        localparam DEPTH = b==1 ? 256 : b==3 ? 32 : 128;
        localparam WIDTH = b==1 ? 96 : b==3 ? 256 : 16;
        reg [WIDTH-1:0] mem [0:DEPTH-1];
        always @(posedge clk) begin
            if (delivered_valid[b]) mem[delivered_addr[b]] <= delivered_data[b];
            if (read_enable[b]) read_data[b] <= #0.5 mem[read_addr[b]];
            // synthesis translate_off
            if (rstn && delivered_valid[b] && delivered_addr[b]>=DEPTH)
                $fatal(1,"NoC write outside bank %0d",b);
            if (rstn && read_enable[b] && read_addr[b]>=DEPTH)
                $fatal(1,"NoC read outside bank %0d",b);
            // synthesis translate_on
        end
        end
    end endgenerate
endmodule
