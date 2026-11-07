`include "global.v"

// Output-stationary dot-product rows. Each column is one input channel;
// partial sums move one PE per cycle. Operands are skewed to meet that sum.
// Kernel positions stream at II=1; all output channels have independent rows.
module systolic_array #(
    parameter INPUT_NUM = 1,
    parameter OUTPUT_NUM = 6,
    parameter WIGHT_SHIFT = 15
) (
    input clk, rstn, en, first_data, last_data,
    input [`WDP*INPUT_NUM-1:0] data_i,
    input [`WDP_BIAS*OUTPUT_NUM-1:0] bias,
    input [`WDP*INPUT_NUM*OUTPUT_NUM-1:0] weight,
    output reg q_en,
    output wire [`WDP*OUTPUT_NUM-1:0] q
);
    // synthesis translate_off
`ifdef REPORT_HIERARCHY
    initial $display("HIERARCHY systolic %m");
`endif
    // synthesis translate_on

    wire [0:INPUT_NUM-1][15:0] data_lanes = data_i;
    wire [0:OUTPUT_NUM-1][0:INPUT_NUM-1][15:0] weights = weight;
    wire [0:OUTPUT_NUM-1][23:0] biases = bias;
    reg [INPUT_NUM-1:0] valid_pipe, first_pipe, last_pipe;
    reg [`WDP_BIAS*OUTPUT_NUM-1:0] bias_pipe [0:INPUT_NUM-1];
    integer t;
    always @(posedge clk) begin
        if (!rstn) begin
            valid_pipe <= 0;
            first_pipe <= 0;
            last_pipe <= 0;
            q_en <= 0;
        end else begin
            valid_pipe[0] <= en;
            first_pipe[0] <= first_data;
            last_pipe[0] <= last_data;
            for (t=1; t<INPUT_NUM; t=t+1) begin
                valid_pipe[t] <= valid_pipe[t-1];
                first_pipe[t] <= first_pipe[t-1];
                last_pipe[t] <= last_pipe[t-1];
            end
            q_en <= valid_pipe[INPUT_NUM-1] && last_pipe[INPUT_NUM-1];
        end
        if (en && first_data) bias_pipe[0] <= bias;
        for (t=1; t<INPUT_NUM; t=t+1)
            if (valid_pipe[t-1] && first_pipe[t-1]) bias_pipe[t] <= bias_pipe[t-1];
    end
    genvar r,c,s;
    generate for (r=0; r<OUTPUT_NUM; r=r+1) begin: row
        wire [31:0] partial [0:INPUT_NUM];
        assign partial[0] = 0;
        for (c=0; c<INPUT_NUM; c=c+1) begin: col
            wire [15:0] d, w;
            if (c==0) begin: direct
                assign d=data_lanes[c];
                assign w=weights[r][c];
            end else begin: skew
                reg [15:0] ds [0:c-1];
                reg [15:0] ws [0:c-1];
                always @(posedge clk) begin
                    if (en) begin
                        ds[0] <= data_lanes[c];
                        ws[0] <= weights[r][c];
                    end
                end
                for (s=1; s<c; s=s+1) begin: delay_operand
                    always @(posedge clk) begin
                        if (valid_pipe[s-1]) begin
                            ds[s] <= ds[s-1];
                            ws[s] <= ws[s-1];
                        end
                    end
                end
                assign d=ds[c-1];
                assign w=ws[c-1];
            end
            reg [31:0] psum;
            wire token = c==0 ? en : valid_pipe[c-1];
            // Operand isolation: a zero activation bypasses the multiplier.
            wire signed [15:0] isolated_data = token ? $signed(d) : 16'sd0;
            wire signed [15:0] isolated_weight = token && d!=0 ? $signed(w) : 16'sd0;
            wire signed [31:0] product = isolated_data*isolated_weight;
            always @(posedge clk) begin
                if (!rstn) psum <= 0;
                else if (token) psum <= partial[c] + product;
            end
            assign partial[c+1]=psum;
        end
        wire [0:OUTPUT_NUM-1][23:0] delayed_bias = bias_pipe[INPUT_NUM-1];
        reg [31:0] accumulator;
        always @(posedge clk) begin
            if (!rstn) accumulator <= 0;
            else if (valid_pipe[INPUT_NUM-1]) begin
                if (first_pipe[INPUT_NUM-1])
                    accumulator <= partial[INPUT_NUM] + {{8{delayed_bias[r][23]}}, delayed_bias[r]};
                else accumulator <= accumulator + partial[INPUT_NUM];
            end
        end
        // Match the original wraparound and truncation, including no saturation.
        assign q[(OUTPUT_NUM-r)*16-1 -:16] = accumulator[WIGHT_SHIFT +:16];
    end endgenerate
endmodule
