`include "global.v"

//=============================================================================
// systolic_conv -- a full convolution layer built from systolic rows
//
// Replaces the iterator + conv/acc/mac chain for one layer.  The baseline
// walks (batch, row, col, ky, kx) and does ONE multiply per clock; this walks
// (row, col) only and does K*K multiplies per clock, because the kernel taps
// are unrolled into hardware instead of into time.
//
//   baseline conv1 :  784 positions * 25 taps = 19600 clocks
//   systolic conv1 : ~1032 clocks             (about 19x fewer)
//
// STRUCTURE
//   linebuf         turns the raster stream into K vertical taps
//   systolic_row[K] one chain per kernel row; the horizontal K comes from the
//                   pixel marching PE to PE, so no KxK register file exists
//   adder tree      sums the K row results, adds bias, rescales
//
// BIT EXACTNESS
//   The baseline forms  bias + SUM(25 products)  in a 32-bit register that is
//   allowed to wrap, then takes q_mac_acc[30:15].  This module forms the same
//   sum in a different ORDER.  Two's-complement addition is associative even
//   through overflow, so the 32-bit total is identical bit for bit, and the
//   same slice is taken.  Output must match the baseline exactly, not merely
//   to within rounding.
//
// SCOPE
//   INPUT_NUM == 1 (conv1).  conv2 needs the plane streamed once per input
//   channel with partial sums held between passes; that is the next module.
//=============================================================================
module systolic_conv #(
	parameter INPUT_NUM   = 1,
	parameter OUTPUT_NUM  = 6,
	parameter K           = 5,
	parameter IN_W        = 32,
	parameter IN_H        = 32,
	parameter WIGHT_SHIFT = 15
	)(
	input										clk,
	input										rstn,
	input										go,

	// weight / bias ROM ports (unchanged ROMs, read K*K times at layer start)
	output reg	[15:0]							aa_weight,
	input		[`WDP*INPUT_NUM*OUTPUT_NUM-1:0]	qa_weight,
	output reg	[`W_OUPTUT_BATCH:0]				aa_bias,
	input		[`WDP_BIAS*OUTPUT_NUM-1:0]		qa_bias,

	// source plane, read once per pixel in raster order
	output reg	[15:0]							aa_data,
	output reg									cena_data,
	input		[`WDP*INPUT_NUM-1:0]			qa_data,

	output reg									q_en,
	output reg	[`WDP*OUTPUT_NUM-1:0]			q,
	output reg									ready
	);

	localparam	OUT_W    = IN_W - K + 1;
	localparam	OUT_H    = IN_H - K + 1;
	localparam	NPIX     = IN_W * IN_H;
	localparam	NTAP     = K * K;
	// Pixels are fed for NPIX cycles, then the pipeline is flushed.  The last
	// valid window closes 2*(K-1) cycles after its final pixel entered, and
	// n trails cnt by the two cycles of address+SRAM latency.
	localparam	STREAM_N = NPIX + 2*K + 2;

	//=========================================================================
	// control
	//=========================================================================
	localparam	S_IDLE = 2'd0,
				S_WLD  = 2'd1,
				S_RUN  = 2'd2,
				S_DONE = 2'd3;

	reg	[1:0]	state;
	reg	[15:0]	cnt;

	always @(`CLK_RST_EDGE)
		if (`RST) begin
			state <= S_IDLE;
			cnt   <= 0;
		end else case (state)
			S_IDLE:	if (go) begin state <= S_WLD; cnt <= 0; end
			// read the weight ROM once per tap; +2 covers its read latency
			S_WLD:	if (cnt == NTAP + 1) begin state <= S_RUN; cnt <= 0; end
					else cnt <= cnt + 1'b1;
			S_RUN:	if (cnt == STREAM_N - 1) begin state <= S_DONE; cnt <= 0; end
					else cnt <= cnt + 1'b1;
			S_DONE:	state <= S_IDLE;
		endcase

	always @(`CLK_RST_EDGE)
		if (`RST)	ready <= 0;
		else		ready <= (state == S_DONE);

	//=========================================================================
	// weight preload -- this is what "weight stationary" buys
	//
	// Each PE latches once, when its own tap index appears on the ROM output.
	// The ROM is read K*K times per frame instead of once per multiply, which
	// is a 19x reduction in weight bandwidth for conv1.
	//=========================================================================
	always @(`CLK_RST_EDGE)
		if (`RST)					aa_weight <= 0;
		else if (state == S_WLD)	aa_weight <= cnt[15:0];
		else						aa_weight <= 0;

	always @(`CLK_RST_EDGE)
		if (`RST)	aa_bias <= 0;
		else		aa_bias <= 0;			// OUTPUT_BATCH == 1 for conv1

	// ROM latency is one clock, so the tap index that qa_weight belongs to is
	// the address issued one cycle earlier.
	reg	[15:0]	wtap;
	reg			wld_v;
	always @(`CLK_RST_EDGE)
		if (`RST) begin
			wtap  <= 0;
			wld_v <= 0;
		end else begin
			wtap  <= aa_weight;
			wld_v <= (state == S_WLD);
		end

	wire	[0:OUTPUT_NUM-1][0:INPUT_NUM-1][`WD:0]	w_rom  = qa_weight;
	wire	[0:OUTPUT_NUM-1][`WD_BIAS:0]			bias_in = qa_bias;

	//=========================================================================
	// raster scan of the source plane
	//=========================================================================
	wire	run = (state == S_RUN);

	always @(`CLK_RST_EDGE)
		if (`RST)		aa_data <= 0;
		else if (run)	aa_data <= (cnt < NPIX) ? cnt[15:0] : 16'd0;
		else			aa_data <= 0;

	// lenet.v gates the weight and bias ROMs with this same enable, so it must
	// be asserted during the weight-load phase too -- not just while streaming
	// pixels.  Reading the source SRAM during S_WLD is harmless: feed_v is low,
	// so nothing enters the line buffer.
	always @(`CLK_RST_EDGE)
		if (`RST)		cena_data <= 1;
		else			cena_data <= ~(run || (state == S_WLD));

	// Two stages of delay, not one.  aa_data is registered out of this module
	// (one clock) and the source SRAM registers its read (a second clock), so
	// the pixel for address k only appears on qa_data two cycles after cnt==k.
	// n must name the pixel that is actually on qa_data right now, otherwise
	// every window is shifted by one column.
	reg			feed_v0, feed_v;
	reg	[15:0]	n0, n;
	always @(`CLK_RST_EDGE)
		if (`RST) begin
			feed_v0 <= 0;	feed_v <= 0;
			n0      <= 0;	n      <= 0;
		end else begin
			feed_v0 <= run;
			n0      <= run ? cnt : 16'd0;
			feed_v  <= feed_v0;
			n       <= n0;
		end

	wire	[`WDP*INPUT_NUM-1:0]	pix = (n < NPIX) ? qa_data : {(`WDP*INPUT_NUM){1'b0}};

	//=========================================================================
	// line buffer -> K vertical taps
	//=========================================================================
	wire	[`WDP*INPUT_NUM*K-1:0]			lb_q;
	wire	[0:K-1][0:INPUT_NUM-1][`WD:0]	tap = lb_q;

	linebuf #(
		.K		(K),
		.WIDTH	(IN_W),
		.NCH	(INPUT_NUM)
		)linebuf(
		.clk	(clk),
		.rstn	(rstn),
		.en		(feed_v),
		.clr	(state == S_IDLE),
		.d_in	(pix),
		.d_out	(lb_q)
		);

	//=========================================================================
	// OUTPUT_NUM arrays, each K systolic rows of K PEs
	//
	// Tap ordering: pe.v accumulates so that w[0] meets the NEWEST sample, so
	// the horizontal taps go in reversed (PE j holds kx = K-1-j).  The
	// vertical taps are not reversed: systolic row r is fed line-buffer tap r,
	// which is input row (out_row + r), so it holds ky = r.
	//=========================================================================
	wire	[0:OUTPUT_NUM-1][0:K-1][`WDP*2-1:0]	row_q;

	genvar o, ky, j;
	generate
		for (o = 0; o < OUTPUT_NUM; o = o + 1) begin : gen_out
			for (ky = 0; ky < K; ky = ky + 1) begin : gen_ky

				// Every lane carries whichever tap the ROM is presenting now;
				// w_ld_row picks the single PE that latches it this cycle.
				wire	[`WDP*K-1:0]	w_row = {K{w_rom[o][0]}};
				wire	[0:K-1]			w_ld_row;

				for (j = 0; j < K; j = j + 1) begin : gen_pe_ld
					// PE j holds kernel column K-1-j, so it latches when the
					// ROM is presenting tap (ky, K-1-j).
					assign w_ld_row[j] = wld_v && (wtap == ky*K + (K-1-j));
				end

				systolic_row #(.K(K)) srow(
					.clk	(clk),
					.rstn	(rstn),
					.en		(feed_v),
					.w_ld	(w_ld_row),
					.w_in	(w_row),
					.d_in	(tap[ky][0]),
					.p_out	(row_q[o][ky])
					);
			end
		end
	endgenerate

	//=========================================================================
	// vertical reduction, bias, rescale
	//=========================================================================
	reg	[0:OUTPUT_NUM-1][`WDP*2-1:0]	rsum;
	integer	oi, ri;
	always @(`CLK_RST_EDGE)
		if (`RST)
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) rsum[oi] <= 0;
		else
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) begin
				rsum[oi] <= $signed(row_q[oi][0]) + $signed(row_q[oi][1])
				          + $signed(row_q[oi][2]) + $signed(row_q[oi][3])
				          + $signed(row_q[oi][4]);
			end

	// baseline takes q_mac_acc[`WDP*2-1:WIGHT_SHIFT] into a `WDP-wide reg,
	// which keeps bits [`WD+WIGHT_SHIFT : WIGHT_SHIFT].  Same slice here.
	reg	[0:OUTPUT_NUM-1][`WD:0]	qv;
	always @(`CLK_RST_EDGE)
		if (`RST)
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) qv[oi] <= 0;
		else
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) begin
				qv[oi] <= ($signed(rsum[oi]) + $signed(bias_in[oi]))
				          >>> WIGHT_SHIFT;
			end

	always @(*) q = qv;

	//=========================================================================
	// output validity
	//
	// A row chain's result after cycle n covers pixel indices n-(K-1)-m for
	// m = 0..K-1, so the window's leftmost pixel is base = n - 2*(K-1).
	// It is a real output only when that window sits inside one image row and
	// inside the valid output rectangle.
	//=========================================================================
	localparam	LAT = 2*(K-1);

	wire	[15:0]	base    = n - LAT;
	wire			base_ok = feed_v && (n >= LAT);
	wire	[15:0]	ocol    = base % IN_W;
	wire	[15:0]	orow    = base / IN_W;

	wire	win_v = base_ok && (ocol <= IN_W - K) && (orow >= K-1) && (orow < IN_H);

	// two register stages between the row output and q
	reg	[1:0]	win_v_d;
	always @(`CLK_RST_EDGE)
		if (`RST)	win_v_d <= 0;
		else		win_v_d <= {win_v_d[0], win_v};

	always @(`CLK_RST_EDGE)
		if (`RST)	q_en <= 0;
		else		q_en <= win_v_d[1];

endmodule
