`timescale 1ns/1ps
// Fuse 2x2/stride-2 max pooling and ReLU at the NoC destination.
// One previous row plus one left sample per channel replaces a full map.
module streaming_pool #(parameter WIDTH=28, CHANNELS=6)(
    input clk, rstn, start, valid,
    input [CHANNELS*16-1:0] data_i,
    output reg [CHANNELS*16-1:0] q,
    output reg q_en, done
);
    // synthesis translate_off
`ifdef REPORT_HIERARCHY
    initial $display("HIERARCHY pool %m");
`endif
    // synthesis translate_on

    integer x,y;
    always @(posedge clk) begin
        if(!rstn || start) begin x<=0;y<=0;q_en<=0;done<=0;end
        else begin
            q_en<=0;done<=0;
            if(valid) begin
                q_en<=x%2==1 && y%2==1;
                done<=x==WIDTH-1 && y==WIDTH-1;
                if(x==WIDTH-1) begin x<=0;y<=y+1;end
                else x<=x+1;
            end
        end
    end
    genvar c;
    generate for(c=0;c<CHANNELS;c=c+1) begin: channel
        reg signed [15:0] previous_row [0:WIDTH-1];
        reg signed [15:0] left;
        wire signed [15:0] sample=data_i[c*16 +:16];
        reg signed [15:0] maximum;
        always @* begin
            maximum=sample;
            if(left>maximum) maximum=left;
            if(previous_row[x]>maximum) maximum=previous_row[x];
            if(x>0 && previous_row[x-1]>maximum) maximum=previous_row[x-1];
        end
        always @(posedge clk) if(rstn && valid) begin
            left<=sample;
            if(y%2==0) previous_row[x]<=sample;
            if(x%2==1 && y%2==1) q[c*16 +:16]<= maximum<0 ? 16'd0 : maximum;
        end
    end endgenerate
endmodule
