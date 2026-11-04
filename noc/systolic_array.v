// Copyright (c) 2024 - Systolic Array for CNN Convolution
// High-throughput 2D systolic array with weight-stationary dataflow
// Optimized for CNN convolution operations

`include "global.v"

// Systolic Array Processing Element (PE)
module systolic_pe (
    input                clk,
    input                rstn,
    input                enable,
    
    // Weight loading
    input        [`WD:0] weight_in,
    input                weight_load,
    
    // Data flow (from west to east)
    input        [`WD:0] data_in,
    output reg   [`WD:0] data_out,
    
    // Partial sum flow (from north to south)
    input      [2*`WDP-1:0] psum_in,
    output reg [2*`WDP-1:0] psum_out,
    
    // Control
    input                clear_acc
);
    
    // Local weight register (weight-stationary)
    reg [`WD:0] weight_reg;
    
    // Accumulator for partial sum
    reg [2*`WDP-1:0] accumulator;
    
    // MAC operation
    wire signed [`WD:0] data_s = data_in;
    wire signed [`WD:0] weight_s = weight_reg;
    wire signed [2*`WDP-1:0] product = data_s * weight_s;
    wire signed [2*`WDP-1:0] new_psum = psum_in + product;
    
    // Weight loading (stays in PE for all input activations)
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            weight_reg <= 0;
        else if (weight_load)
            weight_reg <= weight_in;
    end
    
    // Data propagation (flows horizontally)
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            data_out <= 0;
        else if (enable)
            data_out <= data_in;
    end
    
    // Partial sum accumulation and propagation (flows vertically)
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            psum_out <= 0;
            accumulator <= 0;
        end else if (clear_acc) begin
            accumulator <= 0;
            psum_out <= 0;
        end else if (enable) begin
            accumulator <= new_psum;
            psum_out <= new_psum;
        end
    end
    
endmodule

// 2D Systolic Array for Convolution
// Size: ARRAY_SIZE x ARRAY_SIZE
// Supports variable kernel sizes up to ARRAY_SIZE x ARRAY_SIZE
module systolic_array #(
    parameter ARRAY_SIZE = 8,  // 8x8 array for 5x5 kernels with room for growth
    parameter INPUT_CHANNELS = 6,
    parameter OUTPUT_CHANNELS = 16
) (
    input                      clk,
    input                      rstn,
    input                      enable,
    
    // Weight loading interface
    input  [ARRAY_SIZE-1:0][`WD:0]     weight_row_in,  // One row at a time
    input                              weight_load,
    input  [2:0]                       weight_row_addr,
    
    // Data input (multiple channels can enter per cycle)
    input  [ARRAY_SIZE-1:0][`WD:0]     data_col_in,
    
    // Partial sum output (bottom of array)
    output [ARRAY_SIZE-1:0][2*`WDP-1:0] psum_col_out,
    output                              psum_valid,
    
    // Control
    input                              clear_acc,
    input                              compute_enable
);

    // Internal PE array
    wire [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][`WD:0] data_h;  // Horizontal data flow
    wire [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][2*`WDP-1:0] psum_v; // Vertical psum flow
    
    // Weight loading registers
    reg [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][`WD:0] weight_array;
    
    genvar i, j;
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : col
                
                // Instantiate PE
                systolic_pe pe (
                    .clk(clk),
                    .rstn(rstn),
                    .enable(compute_enable),
                    
                    .weight_in(weight_row_in[j]),
                    .weight_load(weight_load && (weight_row_addr == i)),
                    
                    .data_in((j == 0) ? data_col_in[i] : data_h[i][j-1]),
                    .data_out(data_h[i][j]),
                    
                    .psum_in((i == 0) ? {2*`WDP{1'b0}} : psum_v[i-1][j]),
                    .psum_out(psum_v[i][j]),
                    
                    .clear_acc(clear_acc)
                );
                
            end
        end
    endgenerate
    
    // Output assignment (bottom row of array)
    assign psum_col_out = psum_v[ARRAY_SIZE-1];
    
    // Valid signal generation (delayed by array latency)
    reg [ARRAY_SIZE:0] valid_shift;
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            valid_shift <= 0;
        else
            valid_shift <= {valid_shift[ARRAY_SIZE-1:0], compute_enable};
    end
    assign psum_valid = valid_shift[ARRAY_SIZE];

endmodule

// Systolic Array Controller
// Manages data feeding, weight loading, and output collection
module systolic_controller #(
    parameter ARRAY_SIZE = 8,
    parameter KERNEL_SIZE = 5,
    parameter INPUT_WIDTH = 14,
    parameter INPUT_HEIGHT = 14,
    parameter INPUT_CHANNELS = 6,
    parameter OUTPUT_CHANNELS = 16
) (
    input                clk,
    input                rstn,
    input                start,
    output reg           done,
    
    // Input feature map interface
    input  [`WD:0]       input_data,
    input                input_valid,
    output reg           input_ready,
    
    // Weight interface
    input  [`WD:0]       weight_data,
    input                weight_valid,
    output reg           weight_ready,
    
    // Output feature map interface  
    output reg [`WD:0]   output_data,
    output reg           output_valid,
    input                output_ready,
    
    // NoC interface for high-bandwidth transfers
    output reg [`NOC_DATA_WIDTH-1:0] noc_out_data,
    output reg                       noc_out_valid,
    input                            noc_out_ready
);

    // State machine
    localparam IDLE = 3'd0;
    localparam LOAD_WEIGHTS = 3'd1;
    localparam COMPUTE = 3'd2;
    localparam DRAIN = 3'd3;
    localparam DONE = 3'd4;
    
    reg [2:0] state;
    reg [$clog2(KERNEL_SIZE*KERNEL_SIZE*OUTPUT_CHANNELS):0] weight_cnt;
    reg [$clog2(INPUT_WIDTH*INPUT_HEIGHT*INPUT_CHANNELS):0] data_cnt;
    reg [$clog2(INPUT_WIDTH*INPUT_HEIGHT*OUTPUT_CHANNELS):0] output_cnt;
    
    // Systolic array connections
    wire [ARRAY_SIZE-1:0][`WD:0] weight_row_in;
    reg weight_load;
    reg [2:0] weight_row_addr;
    
    wire [ARRAY_SIZE-1:0][`WD:0] data_col_in;
    wire [ARRAY_SIZE-1:0][2*`WDP-1:0] psum_col_out;
    wire psum_valid;
    
    reg clear_acc, compute_enable;
    
    // Instantiate systolic array
    systolic_array #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .INPUT_CHANNELS(INPUT_CHANNELS),
        .OUTPUT_CHANNELS(OUTPUT_CHANNELS)
    ) sa (
        .clk(clk),
        .rstn(rstn),
        .enable(1'b1),
        .weight_row_in(weight_row_in),
        .weight_load(weight_load),
        .weight_row_addr(weight_row_addr),
        .data_col_in(data_col_in),
        .psum_col_out(psum_col_out),
        .psum_valid(psum_valid),
        .clear_acc(clear_acc),
        .compute_enable(compute_enable)
    );
    
    // Weight and data buffering (simple implementation)
    reg [KERNEL_SIZE*KERNEL_SIZE*OUTPUT_CHANNELS-1:0][`WD:0] weight_buffer;
    reg [INPUT_WIDTH*INPUT_HEIGHT*INPUT_CHANNELS-1:0][`WD:0] input_buffer;
    
    // State machine
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            done <= 0;
            weight_cnt <= 0;
            data_cnt <= 0;
            output_cnt <= 0;
            weight_load <= 0;
            compute_enable <= 0;
            clear_acc <= 1;
            input_ready <= 0;
            weight_ready <= 0;
            output_valid <= 0;
            noc_out_valid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= LOAD_WEIGHTS;
                        weight_ready <= 1;
                        weight_cnt <= 0;
                        clear_acc <= 1;
                    end
                end
                
                LOAD_WEIGHTS: begin
                    // Load weights into array
                    if (weight_valid && weight_ready) begin
                        weight_buffer[weight_cnt] <= weight_data;
                        weight_cnt <= weight_cnt + 1;
                        
                        // Check if all weights loaded
                        if (weight_cnt == KERNEL_SIZE*KERNEL_SIZE*OUTPUT_CHANNELS-1) begin
                            weight_ready <= 0;
                            state <= COMPUTE;
                            input_ready <= 1;
                            data_cnt <= 0;
                            clear_acc <= 0;
                        end
                    end
                end
                
                COMPUTE: begin
                    // Feed input data and compute
                    compute_enable <= 1;
                    if (input_valid && input_ready) begin
                        input_buffer[data_cnt] <= input_data;
                        data_cnt <= data_cnt + 1;
                        
                        if (data_cnt == INPUT_WIDTH*INPUT_HEIGHT*INPUT_CHANNELS-1) begin
                            input_ready <= 0;
                            state <= DRAIN;
                        end
                    end
                    
                    // Collect outputs as they become valid
                    if (psum_valid) begin
                        // Scale output and send via NoC in bursts
                        output_data <= psum_col_out[0][2*`WDP-1:`WIGHT_SHIFT];
                        output_valid <= 1;
                        output_cnt <= output_cnt + 1;
                    end
                end
                
                DRAIN: begin
                    // Drain remaining outputs from pipeline
                    if (output_cnt == INPUT_WIDTH*INPUT_HEIGHT*OUTPUT_CHANNELS-1) begin
                        state <= DONE;
                        compute_enable <= 0;
                    end
                end
                
                DONE: begin
                    done <= 1;
                    output_valid <= 0;
                    if (!start)
                        state <= IDLE;
                end
            endcase
        end
    end
    
    // Connect weight and data to array (simplified - assumes proper timing)
    assign weight_row_in = weight_buffer[ARRAY_SIZE-1:0];
    assign data_col_in = input_buffer[ARRAY_SIZE-1:0];

endmodule

// NoC Packet Generator for Systolic Array Outputs
// Converts systolic array output streams into NoC packets
module systolic_noc_interface #(
    parameter ROUTER_X = 0,
    parameter ROUTER_Y = 0,
    parameter DEST_X = 1,
    parameter DEST_Y = 1
) (
    input                      clk,
    input                      rstn,
    
    // Systolic array output
    input  [`WD:0]             sa_data,
    input                      sa_valid,
    output                     sa_ready,
    
    // NoC output
    output reg [`NOC_FLIT_WIDTH-1:0] noc_flit,
    output reg                       noc_valid,
    input                            noc_ready
);

    // Packet assembly state machine
    localparam IDLE = 2'd0;
    localparam HEAD = 2'd1;
    localparam BODY = 2'd2;
    localparam TAIL = 2'd3;
    
    reg [1:0] state;
    reg [3:0] flit_cnt;
    reg [255:0] data_buffer;  // Accumulate multiple data items per packet
    reg [3:0] buffer_cnt;
    
    assign sa_ready = (state == IDLE || state == BODY) && (buffer_cnt < 16);
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            noc_valid <= 0;
            noc_flit <= 0;
            flit_cnt <= 0;
            buffer_cnt <= 0;
            data_buffer <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (sa_valid && sa_ready) begin
                        // Start new packet
                        data_buffer[`WD:0] <= sa_data;
                        buffer_cnt <= 1;
                        state <= BODY;
                    end
                end
                
                BODY: begin
                    if (sa_valid && sa_ready) begin
                        // Accumulate data
                        data_buffer[(buffer_cnt+1)*16-1 -: 16] <= sa_data;
                        buffer_cnt <= buffer_cnt + 1;
                        
                        // Send when buffer full
                        if (buffer_cnt == 15) begin
                            state <= HEAD;
                        end
                    end else if (buffer_cnt > 0) begin
                        // Timeout - send partial packet
                        state <= HEAD;
                    end
                end
                
                HEAD: begin
                    if (noc_ready) begin
                        // Send header flit
                        noc_flit <= {2'b00, 4'(DEST_X), 4'(DEST_Y), 4'(ROUTER_X), 4'(ROUTER_Y), 
                                    2'b00, buffer_cnt[3:0], {8{1'b0}}, data_buffer};
                        noc_valid <= 1;
                        state <= TAIL;
                    end
                end
                
                TAIL: begin
                    if (noc_ready) begin
                        noc_valid <= 0;
                        buffer_cnt <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
