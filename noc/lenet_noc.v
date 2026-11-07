// Copyright (c) 2018  LulinChen, All Rights Reserved
// AUTHOR : 	LulinChen
// AUTHOR'S EMAIL : lulinchen@aliyun.com 
// Enhanced datapath: systolic arithmetic, routed activations, fused pooling.
// See novelty.md for architecture and measured rather than projected results.
`include "global.v"

module lenet_noc (
    input              clk,
    input              rstn,
    input              go,
    output             cena_src,
    output     [  9:0] aa_src,
    input      [`WD:0] qa_src,
    output reg [  3:0] digit,
    output             ready
);


  wire [5:0] net_valid, net_ready, read_enable, delivered_valid;
  wire [5:0][9:0] delivered_addr;
  wire [5:0][255:0] delivered_data;
  wire [5:0][2:0] net_dest;
  wire [5:0][9:0] net_addr, read_addr;
  wire [5:0][255:0] net_data, read_data;
  activation_noc activation_network (
      .clk(clk), .rstn(rstn), .in_valid(net_valid), .in_ready(net_ready),
      .in_dest(net_dest), .in_addr(net_addr), .in_data(net_data),
      .read_enable(read_enable), .read_addr(read_addr), .read_data(read_data),
      .delivered_valid(delivered_valid), .delivered_addr(delivered_addr),
      .delivered_data(delivered_data)
  );

  wire [                             9:0] aa_weight_conv1;
  wire [      `WDP*`OUTPUT_NUM_CONV1-1:0] qa_weight_conv1;

  wire [               `W_OUPTUT_BATCH:0] aa_bias_conv1;
  wire [`WDP_BIAS*`OUTPUT_NUM_CONV1 -1:0] qa_bias_conv1;

  wieght_conv1_rom wieght_conv1_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_weight_conv1),
      .cena(cena_src),
      .qa  (qa_weight_conv1)
  );
  bias_conv1_rom bias_conv1_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_bias_conv1),
      .cena(cena_src),
      .qa  (qa_bias_conv1)
  );
  wire conv1_go = go;
  iterator #(
      .OUTPUT_BATCH (`OUTPUT_BATCH_CONV1),
      .KERNEL_SIZEX (`KERNEL_SIZEX_CONV1),
      .KERNEL_SIZEY (`KERNEL_SIZEY_CONV1),
      .STEP   (1),
      .INPUT_WIDTH (`INPUT_WIDTH),
      .INPUT_HEIGHT (`INPUT_HEIGHT)
  ) iterator_conv1 (
      .clk       (clk),
      .rstn      (rstn),
      .go        (conv1_go),
      .first_data(first_data),
      .last_data (last_data),
      .aa_bias   (aa_bias_conv1),
      .aa_data   (aa_src),
      .aa_weight (aa_weight_conv1),
      .cena      (cena_src),
      .ready     (conv1_ready)
  );

  reg [51:0] first_data_d;
  always @(*) first_data_d[0] = first_data;
  always @(`CLK_RST_EDGE)
    if (`RST) first_data_d[51:1] <= 0;
    else first_data_d[51:1] <= first_data_d;
  reg [15:0] last_data_d;
  always @(*) last_data_d[0] = last_data;
  always @(`CLK_RST_EDGE)
    if (`RST) last_data_d[15:1] <= 0;
    else last_data_d[15:1] <= last_data_d;

  reg [15:0] cena_src_d;
  always @(*) cena_src_d[0] = cena_src;
  always @(`CLK_RST_EDGE)
    if (`RST) cena_src_d[15:1] <= 0;
    else cena_src_d[15:1] <= cena_src_d;
  wire [`WDP*`OUTPUT_NUM_CONV1 -1:0] q_conv1;

  systolic_array #(
      .INPUT_NUM  (`INPUT_NUM),
      .OUTPUT_NUM (`OUTPUT_NUM),
      .WIGHT_SHIFT(`WIGHT_SHIFT)
  ) conv1 (
      .clk       (clk),
      .rstn      (rstn),
      .en        (~cena_src_d[1]),
      .first_data(first_data_d[1]),
      .last_data (last_data_d[1]),
      .data_i    (qa_src),
      .bias      (qa_bias_conv1),
      .weight    (qa_weight_conv1),
      .q         (q_conv1),
      .q_en      (q_conv1_en)
  );

  reg  [9:0] ab_conv1_buf;
  reg  [95:0] db_conv1_buf;
  reg    cenb_conv1_buf;

  assign net_valid[0] = ~cenb_conv1_buf;
  assign net_dest[0] = 3'd0;
  assign net_addr[0] = ab_conv1_buf;
  assign net_data[0] = db_conv1_buf;
  // These scheduled producers cannot stall: reject any lost transaction.
  // synthesis translate_off
  always @(posedge clk) if (rstn && net_valid[0] && !net_ready[0])
      $fatal(1, "Activation NoC overflow at source 0");
  // synthesis translate_on

  always @(`CLK_RST_EDGE)
    if (`ZST) db_conv1_buf <= 0;
    else if (q_conv1_en) db_conv1_buf <= q_conv1;

  always @(`CLK_RST_EDGE)
    if (`RST) cenb_conv1_buf <= 1;
    else cenb_conv1_buf <= ~q_conv1_en;
  always @(`CLK_RST_EDGE)
    if (`RST) ab_conv1_buf <= 0;
    else if (conv1_go) ab_conv1_buf <= 0;
    else if (!cenb_conv1_buf) ab_conv1_buf <= ab_conv1_buf + 1;

  wire pooling1_go = conv1_go;
  wire pooling1_ready;
  wire [95:0] qa_relu1;
  wire qa_relu1_en;
  // Convolution packets terminate in a streaming pooling endpoint.
  assign read_enable[0] = 1'b0;
  assign read_addr[0] = 0;
  streaming_pool #(.WIDTH(28), .CHANNELS(6)) fused_pool1 (
      .clk(clk), .rstn(rstn), .start(conv1_go),
      .valid(delivered_valid[0]), .data_i(delivered_data[0][95:0]),
      .q(qa_relu1), .q_en(qa_relu1_en), .done(pooling1_ready)
  );

  reg  [7:0] aa_relu1_buf;
  reg    cena_relu1_buf;
  reg  [7:0] ab_relu1_buf;
  reg  [95:0] db_relu1_buf;
  reg    cenb_relu1_buf;
  wire [95:0] qa_relu1_buf;

  assign net_valid[1] = ~cenb_relu1_buf;
  assign net_dest[1] = 3'd1;
  assign net_addr[1] = ab_relu1_buf;
  assign net_data[1] = db_relu1_buf;
  assign read_enable[1] = ~cena_relu1_buf;
  assign read_addr[1] = aa_relu1_buf;
  assign qa_relu1_buf = read_data[1][95:0];
  // These scheduled producers cannot stall: reject any lost transaction.
  // synthesis translate_off
  always @(posedge clk) if (rstn && net_valid[1] && !net_ready[1])
      $fatal(1, "Activation NoC overflow at source 1");
  // synthesis translate_on

  always @(`CLK_RST_EDGE)
    if (`ZST) db_relu1_buf <= 0;
    else if (qa_relu1_en) db_relu1_buf <= qa_relu1;

  always @(`CLK_RST_EDGE)
    if (`RST) cenb_relu1_buf <= 1;
    else cenb_relu1_buf <= ~qa_relu1_en;
  always @(`CLK_RST_EDGE)
    if (`RST) ab_relu1_buf <= 0;
    else if (pooling1_go) ab_relu1_buf <= 0;
    else if (!cenb_relu1_buf) ab_relu1_buf <= ab_relu1_buf + 1;

  //=============================================================================

  wire [`WDP*`OUTPUT_NUM_CONV1*`OUTPUT_NUM_CONV2 -1:0] qa_weight_conv2;
  wire [                                          9:0] aa_weight_conv2;
  wieght_conv2_rom wieght_conv2_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_weight_conv2),
      .cena(cena_relu1_buf),
      .qa  (qa_weight_conv2)
  );

  wire [               `W_OUPTUT_BATCH:0] aa_bias_conv2;
  wire [`WDP_BIAS*`OUTPUT_NUM_CONV2 -1:0] qa_bias_conv2;
  bias_conv2_rom bias_conv2_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_bias_conv2),
      .cena(cena_relu1_buf),
      .qa  (qa_bias_conv2)
  );

  // Start only after the final activation is committed to its endpoint.
  reg conv2_go;
  always @(posedge clk) begin
      if (!rstn) conv2_go <= 0;
      else conv2_go <= delivered_valid[1] && delivered_addr[1] == 10'd195;
  end
  iterator #(
      .OUTPUT_BATCH (`OUTPUT_BATCH_CONV2),
      .KERNEL_SIZEX (`KERNEL_SIZEX_CONV2),
      .KERNEL_SIZEY (`KERNEL_SIZEY_CONV2),
      .STEP   (1),
      .INPUT_WIDTH (`INPUT_WIDTH_CONV2),
      .INPUT_HEIGHT (`INPUT_HEIGHT_CONV2)
  ) iterator_conv2 (

      .clk       (clk),
      .rstn      (rstn),
      .go        (conv2_go),
      .first_data(first_data_conv2),
      .last_data (last_data_conv2),
      .aa_bias   (aa_bias_conv2),
      .aa_data   (aa_relu1_buf),
      .aa_weight (aa_weight_conv2),
      .cena      (cena_relu1_buf),
      .ready     (conv2_ready)
  );

  reg [15:0] cena_relu1_buf_d;
  always @(*) cena_relu1_buf_d[0] = cena_relu1_buf;
  always @(`CLK_RST_EDGE)
    if (`RST) cena_relu1_buf_d[15:1] <= 0;
    else cena_relu1_buf_d[15:1] <= cena_relu1_buf_d;
  reg [15:0] first_data_conv2_d;
  always @(*) first_data_conv2_d[0] = first_data_conv2;
  always @(`CLK_RST_EDGE)
    if (`RST) first_data_conv2_d[15:1] <= 0;
    else first_data_conv2_d[15:1] <= first_data_conv2_d;
  reg [15:0] last_data_conv2_d;
  always @(*) last_data_conv2_d[0] = last_data_conv2;
  always @(`CLK_RST_EDGE)
    if (`RST) last_data_conv2_d[15:1] <= 0;
    else last_data_conv2_d[15:1] <= last_data_conv2_d;


  wire [`WDP*`OUTPUT_NUM_CONV2 -1:0] q_conv2;

  systolic_array #(
      .INPUT_NUM  (`OUTPUT_NUM_CONV1),
      .OUTPUT_NUM (`OUTPUT_NUM_CONV2),
      .WIGHT_SHIFT(`WIGHT_SHIFT)
  ) conv2 (
      .clk       (clk),
      .rstn      (rstn),
      .en        (~cena_relu1_buf_d[1]),
      .first_data(first_data_conv2_d[1]),
      .last_data (last_data_conv2_d[1]),
      .data_i    (qa_relu1_buf),
      .bias      (qa_bias_conv2),
      .weight    (qa_weight_conv2),
      .q         (q_conv2),
      .q_en      (q_conv2_en)
  );

  // 10*10*16
  reg  [6:0] ab_conv2_buf;
  reg  [255:0] db_conv2_buf;
  reg    cenb_conv2_buf;

  assign net_valid[2] = ~cenb_conv2_buf;
  assign net_dest[2] = 3'd2;
  assign net_addr[2] = ab_conv2_buf;
  assign net_data[2] = db_conv2_buf;
  // These scheduled producers cannot stall: reject any lost transaction.
  // synthesis translate_off
  always @(posedge clk) if (rstn && net_valid[2] && !net_ready[2])
      $fatal(1, "Activation NoC overflow at source 2");
  // synthesis translate_on

  always @(`CLK_RST_EDGE)
    if (`ZST) db_conv2_buf <= 0;
    else if (q_conv2_en) db_conv2_buf <= q_conv2;
  always @(`CLK_RST_EDGE)
    if (`RST) cenb_conv2_buf <= 1;
    else cenb_conv2_buf <= ~q_conv2_en;
  always @(`CLK_RST_EDGE)
    if (`RST) ab_conv2_buf <= 0;
    else if (conv2_go) ab_conv2_buf <= 0;
    else if (!cenb_conv2_buf) ab_conv2_buf <= ab_conv2_buf + 1;

  wire pooling2_go = conv2_go;
  wire pooling2_ready;
  wire [255:0] qa_relu2;
  wire qa_relu2_en;
  // Convolution packets terminate in a streaming pooling endpoint.
  assign read_enable[2] = 1'b0;
  assign read_addr[2] = 0;
  streaming_pool #(.WIDTH(10), .CHANNELS(16)) fused_pool2 (
      .clk(clk), .rstn(rstn), .start(conv2_go),
      .valid(delivered_valid[2]), .data_i(delivered_data[2][255:0]),
      .q(qa_relu2), .q_en(qa_relu2_en), .done(pooling2_ready)
  );

  reg  [4:0] aa_relu2_buf;
  reg    cena_relu2_buf;
  reg  [4:0] ab_relu2_buf;
  reg  [255:0] db_relu2_buf;
  reg    cenb_relu2_buf;
  wire [255:0] qa_relu2_buf;

  assign net_valid[3] = ~cenb_relu2_buf;
  assign net_dest[3] = 3'd3;
  assign net_addr[3] = ab_relu2_buf;
  assign net_data[3] = db_relu2_buf;
  assign read_enable[3] = ~cena_relu2_buf;
  assign read_addr[3] = aa_relu2_buf;
  assign qa_relu2_buf = read_data[3][255:0];
  // These scheduled producers cannot stall: reject any lost transaction.
  // synthesis translate_off
  always @(posedge clk) if (rstn && net_valid[3] && !net_ready[3])
      $fatal(1, "Activation NoC overflow at source 3");
  // synthesis translate_on


  always @(`CLK_RST_EDGE)
    if (`ZST) db_relu2_buf <= 0;
    else if (qa_relu2_en) db_relu2_buf <= qa_relu2;

  always @(`CLK_RST_EDGE)
    if (`RST) cenb_relu2_buf <= 1;
    else cenb_relu2_buf <= ~qa_relu2_en;
  always @(`CLK_RST_EDGE)
    if (`RST) ab_relu2_buf <= 0;
    else if (pooling2_go) ab_relu2_buf <= 0;
    else if (!cenb_relu2_buf) ab_relu2_buf <= ab_relu2_buf + 1;

  //======================= FC ================================	

  wire [                    `WDP*`OUTPUT_NUM_CONV2*`OUTPUT_NUM_FC1 -1:0] qa_weight_FC1_rom;
  //	wire		[11:0]											aa_weight_FC1;
  wire [$clog2(`KERNEL_SIZE_FC1*`KERNEL_SIZE_FC1*`OUTPUT_BATCH_FC1)-1:0] aa_weight_FC1;
  wire [                                              `W_OUPTUT_BATCH:0] aa_bias_FC1;
  wire [                                 `WDP_BIAS*`OUTPUT_NUM_FC1 -1:0] qa_bias_FC1;

  wieght_fc1_rom wieght_fc1_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_weight_FC1),
      .cena(cena_relu2_buf),
      .qa  (qa_weight_FC1_rom)
  );
  bias_fc1_rom bias_fc1_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_bias_FC1),
      .cena(cena_relu2_buf),
      .qa  (qa_bias_FC1)
  );


  // Start only after the final activation is committed to its endpoint.
  reg fc1_go;
  always @(posedge clk) begin
      if (!rstn) fc1_go <= 0;
      else fc1_go <= delivered_valid[3] && delivered_addr[3] == 10'd24;
  end
  iterator #(
      .OUTPUT_BATCH (`OUTPUT_BATCH_FC1),
      .KERNEL_SIZEX (`KERNEL_SIZEX_FC1),
      .KERNEL_SIZEY (`KERNEL_SIZEY_FC1),
      .STEP   (1),
      .INPUT_WIDTH (`INPUT_WIDTH_FC1),
      .INPUT_HEIGHT (`INPUT_HEIGHT_FC1)
  ) iterator_FC1 (
      .clk       (clk),
      .rstn      (rstn),
      .go        (fc1_go),
      .first_data(first_data_FC1),
      .last_data (last_data_FC1),
      .aa_bias   (aa_bias_FC1),
      .aa_data   (aa_relu2_buf),
      .aa_weight (aa_weight_FC1),
      .cena      (cena_relu2_buf),
      .ready     (fc1_ready)
  );

  reg [15:0] cena_relu2_buf_d;
  always @(*) cena_relu2_buf_d[0] = cena_relu2_buf;
  always @(`CLK_RST_EDGE)
    if (`RST) cena_relu2_buf_d[15:1] <= 0;
    else cena_relu2_buf_d[15:1] <= cena_relu2_buf_d;
  reg [15:0] first_data_FC1_d;
  always @(*) first_data_FC1_d[0] = first_data_FC1;
  always @(`CLK_RST_EDGE)
    if (`RST) first_data_FC1_d[15:1] <= 0;
    else first_data_FC1_d[15:1] <= first_data_FC1_d;

  reg [15:0] last_data_FC1_d;
  always @(*) last_data_FC1_d[0] = last_data_FC1;
  always @(`CLK_RST_EDGE)
    if (`RST) last_data_FC1_d[15:1] <= 0;
    else last_data_FC1_d[15:1] <= last_data_FC1_d;

  wire [`WDP*`OUTPUT_NUM_FC1 -1:0] q_fc1;
  systolic_array #(
      .INPUT_NUM  (`OUTPUT_NUM_CONV2),
      .OUTPUT_NUM (`OUTPUT_NUM_FC1),
      .WIGHT_SHIFT(`WIGHT_SHIFT)
  ) conv_fc1 (
      .clk       (clk),
      .rstn      (rstn),
      .en        (~cena_relu2_buf_d[1]),
      .first_data(first_data_FC1_d[1]),
      .last_data (last_data_FC1_d[1]),
      .data_i    (qa_relu2_buf),
      .bias      (qa_bias_FC1),
      .weight    (qa_weight_FC1_rom),
      .q         (q_fc1),
      .q_en      (q_fc1_en)
  );

  wire [`WDP*`OUTPUT_NUM_FC1 -1:0] qa_relu_fc1;
  relu #(
      .INPUT_NUM(`OUTPUT_NUM_FC1)  // input plane_num
  ) relu_fc1 (
      .clk   (clk),
      .rstn  (rstn),
      .en    (q_fc1_en),
      .data_i(q_fc1),

      .q_en(qa_relu_fc1_en),
      .q   (qa_relu_fc1)
  );

  reg  [6:0] aa_relu_fc1_buf;
  reg    cena_relu_fc1_buf;
  reg  [6:0] ab_relu_fc1_buf;
  reg  [15:0] db_relu_fc1_buf;
  reg    cenb_relu_fc1_buf;
  wire [15:0] qa_relu_fc1_buf;

  assign net_valid[4] = ~cenb_relu_fc1_buf;
  assign net_dest[4] = 3'd4;
  assign net_addr[4] = ab_relu_fc1_buf;
  assign net_data[4] = db_relu_fc1_buf;
  assign read_enable[4] = ~cena_relu_fc1_buf;
  assign read_addr[4] = aa_relu_fc1_buf;
  assign qa_relu_fc1_buf = read_data[4][15:0];
  // These scheduled producers cannot stall: reject any lost transaction.
  // synthesis translate_off
  always @(posedge clk) if (rstn && net_valid[4] && !net_ready[4])
      $fatal(1, "Activation NoC overflow at source 4");
  // synthesis translate_on
  always @(`CLK_RST_EDGE)
    if (`RST) db_relu_fc1_buf <= 0;
    else if (qa_relu_fc1_en) db_relu_fc1_buf <= qa_relu_fc1;
  always @(`CLK_RST_EDGE)
    if (`RST) cenb_relu_fc1_buf <= 1;
    else cenb_relu_fc1_buf <= ~qa_relu_fc1_en;
  always @(`CLK_RST_EDGE)
    if (`RST) ab_relu_fc1_buf <= 0;
    else if (fc1_go) ab_relu_fc1_buf <= 0;
    else if (!cenb_relu_fc1_buf) ab_relu_fc1_buf <= ab_relu_fc1_buf + 1;

  //=================FC2============================================================

  wire [                        `WDP*`OUTPUT_NUM_FC1*`OUTPUT_NUM_FC2 -1:0] qa_weight_fc2_rom;
  //	wire		[11:0]											aa_weight_fc2;
  wire [$clog2(`KERNEL_SIZEX_FC2*`KERNEL_SIZEY_FC2*`OUTPUT_BATCH_FC2)-1:0] aa_weight_fc2;
  wire [                                                `W_OUPTUT_BATCH:0] aa_bias_fc2;
  wire [                                   `WDP_BIAS*`OUTPUT_NUM_FC2 -1:0] qa_bias_fc2;

  wieght_fc2_rom wieght_fc2_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_weight_fc2),
      .cena(cena_relu_fc1_buf),
      .qa  (qa_weight_fc2_rom)
  );
  bias_fc2_rom bias_fc2_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_bias_fc2),
      .cena(cena_relu_fc1_buf),
      .qa  (qa_bias_fc2)
  );


  // Start only after the final activation is committed to its endpoint.
  reg fc2_go;
  always @(posedge clk) begin
      if (!rstn) fc2_go <= 0;
      else fc2_go <= delivered_valid[4] && delivered_addr[4] == 10'd119;
  end
  iterator #(
      .OUTPUT_BATCH (`OUTPUT_BATCH_FC2),
      .KERNEL_SIZEX (`KERNEL_SIZEX_FC2),
      .KERNEL_SIZEY (`KERNEL_SIZEY_FC2),
      .STEP   (1),
      .INPUT_WIDTH (`INPUT_WIDTH_FC2),
      .INPUT_HEIGHT (`INPUT_HEIGHT_FC2)
  ) iterator_fc2 (
      .clk       (clk),
      .rstn      (rstn),
      .go        (fc2_go),
      .first_data(first_data_fc2),
      .last_data (last_data_fc2),
      .aa_bias   (aa_bias_fc2),
      .aa_data   (aa_relu_fc1_buf),
      .aa_weight (aa_weight_fc2),
      .cena      (cena_relu_fc1_buf),
      .ready     (fc2_ready)
  );

  reg [15:0] cena_relu_fc1_buf_d;
  always @(*) cena_relu_fc1_buf_d[0] = cena_relu_fc1_buf;
  always @(`CLK_RST_EDGE)
    if (`RST) cena_relu_fc1_buf_d[15:1] <= 0;
    else cena_relu_fc1_buf_d[15:1] <= cena_relu_fc1_buf_d;
  reg [15:0] first_data_fc2_d;
  always @(*) first_data_fc2_d[0] = first_data_fc2;
  always @(`CLK_RST_EDGE)
    if (`RST) first_data_fc2_d[15:1] <= 0;
    else first_data_fc2_d[15:1] <= first_data_fc2_d;

  reg [15:0] last_data_fc2_d;
  always @(*) last_data_fc2_d[0] = last_data_fc2;
  always @(`CLK_RST_EDGE)
    if (`RST) last_data_fc2_d[15:1] <= 0;
    else last_data_fc2_d[15:1] <= last_data_fc2_d;

  wire [`WDP*`OUTPUT_NUM_FC2 -1:0] q_fc2;
  systolic_array #(
      .INPUT_NUM  (`OUTPUT_NUM_FC1),
      .OUTPUT_NUM (`OUTPUT_NUM_FC2),
      .WIGHT_SHIFT(`WIGHT_SHIFT)
  ) conv_fc2 (
      .clk       (clk),
      .rstn      (rstn),
      .en        (~cena_relu_fc1_buf_d[1]),
      .first_data(first_data_fc2_d[1]),
      .last_data (last_data_fc2_d[1]),
      .data_i    (qa_relu_fc1_buf),
      .bias      (qa_bias_fc2),
      .weight    (qa_weight_fc2_rom),
      .q         (q_fc2),
      .q_en      (q_fc2_en)
  );

  wire [`WDP*`OUTPUT_NUM_FC2 -1:0] qa_relu_fc2;
  relu #(
      .INPUT_NUM(`OUTPUT_NUM_FC2)  // input plane_num
  ) relu_fc2 (
      .clk   (clk),
      .rstn  (rstn),
      .en    (q_fc2_en),
      .data_i(q_fc2),

      .q_en(qa_relu_fc2_en),
      .q   (qa_relu_fc2)
  );

  reg  [6:0] aa_relu_fc2_buf;
  reg    cena_relu_fc2_buf;
  reg  [6:0] ab_relu_fc2_buf;
  reg  [15:0] db_relu_fc2_buf;
  reg    cenb_relu_fc2_buf;
  wire [15:0] qa_relu_fc2_buf;

  assign net_valid[5] = ~cenb_relu_fc2_buf;
  assign net_dest[5] = 3'd5;
  assign net_addr[5] = ab_relu_fc2_buf;
  assign net_data[5] = db_relu_fc2_buf;
  assign read_enable[5] = ~cena_relu_fc2_buf;
  assign read_addr[5] = aa_relu_fc2_buf;
  assign qa_relu_fc2_buf = read_data[5][15:0];
  // These scheduled producers cannot stall: reject any lost transaction.
  // synthesis translate_off
  always @(posedge clk) if (rstn && net_valid[5] && !net_ready[5])
      $fatal(1, "Activation NoC overflow at source 5");
  // synthesis translate_on
  always @(`CLK_RST_EDGE)
    if (`RST) db_relu_fc2_buf <= 0;
    else if (qa_relu_fc2_en) db_relu_fc2_buf <= qa_relu_fc2;
  always @(`CLK_RST_EDGE)
    if (`RST) cenb_relu_fc2_buf <= 1;
    else cenb_relu_fc2_buf <= ~qa_relu_fc2_en;
  always @(`CLK_RST_EDGE)
    if (`RST) ab_relu_fc2_buf <= 0;
    else if (fc2_go) ab_relu_fc2_buf <= 0;
    else if (!cenb_relu_fc2_buf) ab_relu_fc2_buf <= ab_relu_fc2_buf + 1;

  //=================FC3============================================================

  wire [                        `WDP*`OUTPUT_NUM_FC2*`OUTPUT_NUM_FC3 -1:0] qa_weight_fc3_rom;
  //	wire		[11:0]											aa_weight_fc3;
  wire [$clog2(`KERNEL_SIZEX_FC3*`KERNEL_SIZEY_FC3*`OUTPUT_BATCH_FC3)-1:0] aa_weight_fc3;
  wire [                                                `W_OUPTUT_BATCH:0] aa_bias_fc3;
  wire [                                   `WDP_BIAS*`OUTPUT_NUM_FC3 -1:0] qa_bias_fc3;

  wieght_fc3_rom wieght_fc3_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_weight_fc3),
      .cena(cena_relu_fc2_buf),
      .qa  (qa_weight_fc3_rom)
  );
  bias_fc3_rom bias_fc3_rom (
      .clk (clk),
      .rstn(rstn),
      .aa  (aa_bias_fc3),
      .cena(cena_relu_fc2_buf),
      .qa  (qa_bias_fc3)
  );


  // Start only after the final activation is committed to its endpoint.
  reg fc3_go;
  always @(posedge clk) begin
      if (!rstn) fc3_go <= 0;
      else fc3_go <= delivered_valid[5] && delivered_addr[5] == 10'd83;
  end
  iterator #(
      .OUTPUT_BATCH (`OUTPUT_BATCH_FC3),
      .KERNEL_SIZEX (`KERNEL_SIZEX_FC3),
      .KERNEL_SIZEY (`KERNEL_SIZEY_FC3),
      .STEP   (1),
      .INPUT_WIDTH (`INPUT_WIDTH_FC3),
      .INPUT_HEIGHT (`INPUT_HEIGHT_FC3)
  ) iterator_fc3 (
      .clk       (clk),
      .rstn      (rstn),
      .go        (fc3_go),
      .first_data(first_data_fc3),
      .last_data (last_data_fc3),
      .aa_bias   (aa_bias_fc3),
      .aa_data   (aa_relu_fc2_buf),
      .aa_weight (aa_weight_fc3),
      .cena      (cena_relu_fc2_buf),
      .ready     (fc3_ready)
  );

  reg [15:0] cena_relu_fc2_buf_d;
  always @(*) cena_relu_fc2_buf_d[0] = cena_relu_fc2_buf;
  always @(`CLK_RST_EDGE)
    if (`RST) cena_relu_fc2_buf_d[15:1] <= 0;
    else cena_relu_fc2_buf_d[15:1] <= cena_relu_fc2_buf_d;
  reg [15:0] first_data_fc3_d;
  always @(*) first_data_fc3_d[0] = first_data_fc3;
  always @(`CLK_RST_EDGE)
    if (`RST) first_data_fc3_d[15:1] <= 0;
    else first_data_fc3_d[15:1] <= first_data_fc3_d;

  reg [15:0] last_data_fc3_d;
  always @(*) last_data_fc3_d[0] = last_data_fc3;
  always @(`CLK_RST_EDGE)
    if (`RST) last_data_fc3_d[15:1] <= 0;
    else last_data_fc3_d[15:1] <= last_data_fc3_d;

  wire [`WDP*`OUTPUT_NUM_FC3 -1:0] q_fc3;
  systolic_array #(
      .INPUT_NUM  (`OUTPUT_NUM_FC2),
      .OUTPUT_NUM (`OUTPUT_NUM_FC3),
      .WIGHT_SHIFT(`WIGHT_SHIFT)
  ) conv_fc3 (
      .clk       (clk),
      .rstn      (rstn),
      .en        (~cena_relu_fc2_buf_d[1]),
      .first_data(first_data_fc3_d[1]),
      .last_data (last_data_fc3_d[1]),
      .data_i    (qa_relu_fc2_buf),
      .bias      (qa_bias_fc3),
      .weight    (qa_weight_fc3_rom),
      .q         (q_fc3),
      .q_en      (q_fc3_en)
  );
  reg signed [`WD:0] q_fc_fc3_max;
  reg [3:0] q_fc3_index;
  //reg			[3:0]	digit;
  always @(`CLK_RST_EDGE)
    if (`RST) q_fc3_index <= 0;
    else if (fc3_go) q_fc3_index <= 0;
    else if (q_fc3_en) q_fc3_index <= q_fc3_index + 1;

  wire gt_f = $signed(q_fc3) > $signed(q_fc_fc3_max);
  always @(`CLK_RST_EDGE)
    if (`RST) q_fc_fc3_max <= 0;
    else if (fc3_go) q_fc_fc3_max <= 1 << (`WD);
    else if (q_fc3_en) if (gt_f) q_fc_fc3_max <= q_fc3;
  always @(`CLK_RST_EDGE)
    if (`RST) digit <= 0;
    else if (fc3_go) digit <= 0;
    else if (q_fc3_en) if (gt_f) digit <= q_fc3_index;

  // The tenth logit also updates argmax on this edge.
  reg inference_done;
  always @(posedge clk) begin
      if (!rstn) inference_done <= 0;
      else inference_done <= q_fc3_en && q_fc3_index == 4'd9;
  end
  assign ready = inference_done;

endmodule

