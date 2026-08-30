`include "global.v"

// One cell of a weight-stationary systolic row: multiplier, adder, and a
// register on every output edge, so the critical path stays one MAC however
// long the chain grows.
//
// Data is delayed TWICE per stage and the partial sum ONCE.  With x(t) the
// pixel entering PE0 at clock t, that ratio gives
//     p_out(j,t) = p_out(j-1,t-1) + w[j]*x(t-1-2j) = SUM_m w[m]*x(t-(1+j)-m)
// so every term shares one window.  A 1:1 ratio would make each PE add a
// different tap of the same sample.
//
// Consequence: w[0] meets the newest sample, so taps load reversed.
//
// p_out wraps at `WDP*2 exactly like q_mac_acc in cnn.v, which is what keeps
// the result bit-identical to the baseline.
module pe (
	input									clk,
	input									rstn,
	input									en,
	input									w_ld,
	input			[`WD:0]					w_in,

	input	signed	[`WD:0]					d_in,
	output	reg	signed	[`WD:0]				d_out,

	input	signed	[`WDP*2-1:0]			p_in,
	output	reg	signed	[`WDP*2-1:0]		p_out
	);

	reg		[`WD:0]		w;
	always @(`CLK_RST_EDGE)
		if (`RST)			w <= 0;
		else if (w_ld)		w <= w_in;

	reg	signed	[`WD:0]	d_mid;
	always @(`CLK_RST_EDGE)
		if (`RST) begin
			d_mid <= 0;
			d_out <= 0;
		end else if (en) begin
			d_mid <= d_in;
			d_out <= d_mid;
		end

	// multiplies d_in, not d_mid: d_mid/d_out only hand the sample onward
	always @(`CLK_RST_EDGE)
		if (`RST)			p_out <= 0;
		else if (en)		p_out <= p_in + $signed(d_in) * $signed(w);

endmodule


// K PEs chained into one kernel row.  Emits the dot product of that row
// against the K pixels ending at the sample that entered K clocks ago.
module systolic_row #(
	parameter K = 5
	)(
	input									clk,
	input									rstn,
	input									en,
	input			[0:K-1]					w_ld,	// one per PE; the ROM
	input			[`WDP*K-1:0]			w_in,	// presents one tap at a time
	input	signed	[`WD:0]					d_in,
	output	signed	[`WDP*2-1:0]			p_out
	);

	wire	[0:K-1][`WD:0]			w_tap = w_in;
	wire	signed	[`WD:0]			d_chain	[0:K];
	wire	signed	[`WDP*2-1:0]	p_chain	[0:K];

	assign	d_chain[0] = d_in;
	assign	p_chain[0] = 0;

	genvar i;
	generate
		for (i = 0; i < K; i = i + 1) begin : gen_pe
			pe pe(
				.clk		(clk),
				.rstn		(rstn),
				.en			(en),
				.w_ld		(w_ld[i]),
				.w_in		(w_tap[i]),
				.d_in		(d_chain[i]),
				.d_out		(d_chain[i+1]),
				.p_in		(p_chain[i]),
				.p_out		(p_chain[i+1])
				);
		end
	endgenerate

	assign	p_out = p_chain[K];

endmodule
