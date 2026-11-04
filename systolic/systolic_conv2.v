`include "global.v"

// conv2: same systolic structure as systolic_conv.v, but with six input
// channels.  A K*K array holds one channel's taps at a time, and interleaving
// channels clock by clock would break the chain -- it assumes consecutive
// clocks carry consecutive columns of one stream.  So the plane is streamed
// once per channel, weights reloaded each pass, partial sums held between:
//
//     for c in 0..INPUT_NUM-1:
//         load w[*][c][*][*]                  (K*K clocks)
//         raster-scan the plane, channel c    (IN_W*IN_H clocks)
//         psum[position] += array result
//     emit (psum + bias) >> WIGHT_SHIFT on the final pass
//
// Only one channel enters the line buffer, so it stays NCH=1.
// Timing, tap ordering and the bit-exactness argument are as systolic_conv.v.
module systolic_conv2 #(
	parameter INPUT_NUM   = 6,
	parameter OUTPUT_NUM  = 16,
	parameter K           = 5,
	parameter IN_W        = 14,
	parameter IN_H        = 14,
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
	localparam	OUT_POS  = OUT_W * OUT_H;
	localparam	NPIX     = IN_W * IN_H;
	localparam	NTAP     = K * K;
	localparam	STREAM_N = NPIX + 2*K + 2;
	localparam	LAT      = 2*(K-1);

	localparam	S_IDLE = 2'd0,
				S_WLD  = 2'd1,
				S_RUN  = 2'd2,
				S_DONE = 2'd3;

	reg	[1:0]	state;
	reg	[15:0]	cnt;
	reg	[3:0]	pass;			// which input channel this sweep is for

	wire	last_pass = (pass == INPUT_NUM - 1);

	always @(`CLK_RST_EDGE)
		if (`RST) begin
			state <= S_IDLE;
			cnt   <= 0;
			pass  <= 0;
		end else case (state)
			S_IDLE:	if (go) begin
						state <= S_WLD; cnt <= 0; pass <= 0;
					end
			S_WLD:	if (cnt == NTAP + 1) begin state <= S_RUN; cnt <= 0; end
					else cnt <= cnt + 1'b1;
			S_RUN:	if (cnt == STREAM_N - 1) begin
						cnt <= 0;
						if (last_pass)	state <= S_DONE;
						else begin		state <= S_WLD; pass <= pass + 1'b1; end
					end else cnt <= cnt + 1'b1;
			S_DONE:	begin state <= S_IDLE; pass <= 0; end
		endcase

	always @(`CLK_RST_EDGE)
		if (`RST)	ready <= 0;
		else		ready <= (state == S_DONE);

	always @(`CLK_RST_EDGE)
		if (`RST)					aa_weight <= 0;
		else if (state == S_WLD)	aa_weight <= cnt[15:0];
		else						aa_weight <= 0;

	always @(`CLK_RST_EDGE)
		if (`RST)	aa_bias <= 0;
		else		aa_bias <= 0;			// OUTPUT_BATCH_CONV2 == 1

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

	wire	[0:OUTPUT_NUM-1][0:INPUT_NUM-1][`WD:0]	w_rom   = qa_weight;
	wire	[0:OUTPUT_NUM-1][`WD_BIAS:0]			bias_in = qa_bias;

	wire	run = (state == S_RUN);

	always @(`CLK_RST_EDGE)
		if (`RST)		aa_data <= 0;
		else if (run)	aa_data <= (cnt < NPIX) ? cnt[15:0] : 16'd0;
		else			aa_data <= 0;

	// must cover S_WLD: lenet.v gates the conv2 weight and bias ROMs with this
	always @(`CLK_RST_EDGE)
		if (`RST)		cena_data <= 1;
		else			cena_data <= ~(run || (state == S_WLD));

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

	// only the channel this pass is for enters the line buffer
	wire	[0:INPUT_NUM-1][`WD:0]	din_ch = qa_data;
	wire	[`WDP-1:0]				pix    = (n < NPIX) ? din_ch[pass] : {`WDP{1'b0}};

	wire	[`WDP*K-1:0]		lb_q;
	wire	[0:K-1][`WD:0]		tap = lb_q;

	linebuf #(
		.K		(K),
		.WIDTH	(IN_W),
		.NCH	(1)
		)linebuf(
		.clk	(clk),
		.rstn	(rstn),
		.en		(feed_v),
		.clr	(state == S_WLD),		// flush between passes
		.d_in	(pix),
		.d_out	(lb_q)
		);

	wire	[0:OUTPUT_NUM-1][0:K-1][`WDP*2-1:0]	row_q;

	genvar o, ky, j;
	generate
		for (o = 0; o < OUTPUT_NUM; o = o + 1) begin : gen_out
			for (ky = 0; ky < K; ky = ky + 1) begin : gen_ky

				wire	[`WDP*K-1:0]	w_row = {K{w_rom[o][pass]}};
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
					.d_in	(tap[ky]),
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

	wire	[15:0]	base    = n - LAT;
	wire			base_ok = feed_v && (n >= LAT);
	wire	[15:0]	ocol    = base % IN_W;
	wire	[15:0]	orow    = base / IN_W;

	wire	win_v = base_ok && (ocol <= IN_W - K) && (orow >= K-1) && (orow < IN_H);

	reg	[1:0]	win_v_d;
	always @(`CLK_RST_EDGE)
		if (`RST)	win_v_d <= 0;
		else		win_v_d <= {win_v_d[0], win_v};

	// Positions come out in raster order every pass, so opos is just a counter;
	// one entry is read, updated and rewritten per valid window.
	reg	[0:OUTPUT_NUM-1][`WDP*2-1:0]	psum	[0:OUT_POS-1];
	reg	[15:0]							opos;

	wire	acc_v = win_v_d[1];					// aligned with rsum

	wire	[0:OUTPUT_NUM-1][`WDP*2-1:0]	psum_rd = psum[opos];

	integer	pi;
	always @(`CLK_RST_EDGE)
		if (`RST)					opos <= 0;
		else if (state == S_WLD)	opos <= 0;
		else if (acc_v)				opos <= opos + 1'b1;

	always @(`CLK_RST_EDGE)
		if (acc_v) begin
			for (pi = 0; pi < OUTPUT_NUM; pi = pi + 1)
				psum[opos][pi] <= (pass == 0)
				                ? $signed(rsum[pi])
				                : $signed(psum_rd[pi]) + $signed(rsum[pi]);
		end

	reg	[0:OUTPUT_NUM-1][`WD:0]	qv;
	always @(`CLK_RST_EDGE)
		if (`RST)
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1) qv[oi] <= 0;
		else if (acc_v)
			for (oi = 0; oi < OUTPUT_NUM; oi = oi + 1)
				qv[oi] <= ($signed(psum_rd[oi]) + $signed(rsum[oi])
				          + $signed(bias_in[oi])) >>> WIGHT_SHIFT;

	always @(*) q = qv;

	always @(`CLK_RST_EDGE)
		if (`RST)	q_en <= 0;
		else		q_en <= acc_v && last_pass;

endmodule
