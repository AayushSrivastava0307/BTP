`include "global.v"

// conv1 as systolic arrays: replaces the iterator + conv/acc/mac chain for a
// single-input-channel layer.  Walks (row, col) only and does K*K multiplies
// per clock, because the kernel taps are unrolled into hardware not time.
//
// Forms the same integer sum as the baseline in a different order.  Two's
// complement addition is associative even through overflow, so the 32-bit
// total is identical bit for bit -- output must match exactly, not merely to
// within rounding.
//
// INPUT_NUM == 1 only; conv2 has six input channels, see systolic_conv2.v.
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

	output reg	[15:0]							aa_weight,
	input		[`WDP*INPUT_NUM*OUTPUT_NUM-1:0]	qa_weight,
	output reg	[`W_OUPTUT_BATCH:0]				aa_bias,
	input		[`WDP_BIAS*OUTPUT_NUM-1:0]		qa_bias,

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
	// pixels for NPIX clocks, then flush; n trails cnt by the two clocks of
	// address+SRAM latency
	localparam	STREAM_N = NPIX + 2*K + 2;
	localparam	LAT      = 2*(K-1);

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
			S_WLD:	if (cnt == NTAP + 1) begin state <= S_RUN; cnt <= 0; end
					else cnt <= cnt + 1'b1;
			S_RUN:	if (cnt == STREAM_N - 1) begin state <= S_DONE; cnt <= 0; end
					else cnt <= cnt + 1'b1;
			S_DONE:	state <= S_IDLE;
		endcase

	always @(`CLK_RST_EDGE)
		if (`RST)	ready <= 0;
		else		ready <= (state == S_DONE);

	// Weight preload: each PE latches once, when its own tap appears on the
	// ROM output.  The ROM is read K*K times per frame, not once per multiply.
	always @(`CLK_RST_EDGE)
		if (`RST)					aa_weight <= 0;
		else if (state == S_WLD)	aa_weight <= cnt[15:0];
		else						aa_weight <= 0;

	always @(`CLK_RST_EDGE)
		if (`RST)	aa_bias <= 0;
		else		aa_bias <= 0;			// OUTPUT_BATCH == 1 for conv1

	// ROM latency is one clock, so qa_weight belongs to the address issued
	// one cycle earlier
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

	wire	run = (state == S_RUN);

	always @(`CLK_RST_EDGE)
		if (`RST)		aa_data <= 0;
		else if (run)	aa_data <= (cnt < NPIX) ? cnt[15:0] : 16'd0;
		else			aa_data <= 0;

	// lenet.v gates the weight and bias ROMs with this same enable, so it must
	// cover S_WLD too, or every PE latches zero.  Reading the source SRAM
	// during S_WLD is harmless: feed_v is low.
	always @(`CLK_RST_EDGE)
		if (`RST)		cena_data <= 1;
		else			cena_data <= ~(run || (state == S_WLD));

	// Two stages, not one: aa_data is registered out of here (one clock) and
	// the SRAM registers its read (a second).  n must name the pixel actually
	// on qa_data now, or every window shifts by a column.
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

	// OUTPUT_NUM arrays of K rows of K PEs.  PE j holds kernel column K-1-j
	// (pe.v pairs w[0] with the newest sample); systolic row r holds kernel
	// row r, since it is fed line-buffer tap r = input row out_row + r.
	wire	[0:OUTPUT_NUM-1][0:K-1][`WDP*2-1:0]	row_q;

	genvar o, ky, j;
	generate
		for (o = 0; o < OUTPUT_NUM; o = o + 1) begin : gen_out
			for (ky = 0; ky < K; ky = ky + 1) begin : gen_ky

				// every lane carries the tap the ROM presents now; w_ld_row
				// picks the one PE that latches it
				wire	[`WDP*K-1:0]	w_row = {K{w_rom[o][0]}};
				wire	[0:K-1]			w_ld_row;

				for (j = 0; j < K; j = j + 1) begin : gen_pe_ld
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

	reg	[0:OUTPUT_NUM-1][`WDP*2-1:0]	rsum;
	integer	oi;
	always @(`CLK_RST_EDGE)
		if (`RST)
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) rsum[oi] <= 0;
		else
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1)
				rsum[oi] <= $signed(row_q[oi][0]) + $signed(row_q[oi][1])
				          + $signed(row_q[oi][2]) + $signed(row_q[oi][3])
				          + $signed(row_q[oi][4]);

	// baseline keeps q_mac_acc[`WD+WIGHT_SHIFT : WIGHT_SHIFT]; same slice here
	reg	[0:OUTPUT_NUM-1][`WD:0]	qv;
	always @(`CLK_RST_EDGE)
		if (`RST)
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) qv[oi] <= 0;
		else
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1)
				qv[oi] <= ($signed(rsum[oi]) + $signed(bias_in[oi]))
				          >>> WIGHT_SHIFT;

	always @(*) q = qv;

	// A row chain's result after clock n covers pixels n-(K-1)-m, so the
	// window's leftmost pixel is base = n - 2*(K-1).  Real only when that
	// window sits inside one image row and inside the output rectangle.
	wire	[15:0]	base    = n - LAT;
	wire			base_ok = feed_v && (n >= LAT);
	wire	[15:0]	ocol    = base % IN_W;
	wire	[15:0]	orow    = base / IN_W;

	wire	win_v = base_ok && (ocol <= IN_W - K) && (orow >= K-1) && (orow < IN_H);

	reg	[1:0]	win_v_d;			// two stages, matching rsum -> qv
	always @(`CLK_RST_EDGE)
		if (`RST)	win_v_d <= 0;
		else		win_v_d <= {win_v_d[0], win_v};

	always @(`CLK_RST_EDGE)
		if (`RST)	q_en <= 0;
		else		q_en <= win_v_d[1];

endmodule
