`include "global.v"

//=============================================================================
// pe -- one processing element of a weight-stationary systolic convolution row
//
// Contents are the classic systolic cell: one multiplier, one adder, and
// registers on every output edge.  A PE only ever talks to its immediate
// neighbours, so the critical path is a single MAC no matter how long the
// chain grows.
//
// The weight is loaded once (w_ld) at the start of a frame and then held --
// that is what "weight stationary" means, and it is why the weight ROM gets
// read KxK times per layer instead of once per multiply.
//
// TIMING -- why the data path has two registers and the sum path has one:
//
//   Let x(t) be the pixel entering PE0 at cycle t.  Data is delayed twice per
//   stage, so PE j sees d_in = x(t-2j).  Partial sums are delayed once, so
//
//       p_out(j,t) = p_out(j-1,t-1) + w[j]*x(t-1-2j)
//
//   Expanding gives   p_out(j,t) = SUM_m w[m] * x(t-(1+j)-m)
//
//   Every term shares one window, which only works because the sum marches
//   half as fast as the data.  A 1:1 ratio would make each PE add a different
//   tap of the *same* sample -- the classic mistake.
//
//   Note the ordering that falls out: w[0] multiplies the NEWEST sample in the
//   window.  Kernel taps are therefore loaded reversed; systolic_conv.v does
//   that when it fills the array.
//
// The partial sum is `WDP*2 wide and is allowed to wrap, exactly like
// q_mac_acc in cnn.v.  Two's-complement addition is associative even through
// overflow, so reordering the accumulation cannot change the result -- this is
// what makes the systolic output bit-identical to the baseline.
//=============================================================================
module pe (
	input									clk,
	input									rstn,
	input									en,		// advance the pipeline
	input									w_ld,	// latch the stationary weight
	input			[`WD:0]					w_in,

	input	signed	[`WD:0]					d_in,
	output	reg	signed	[`WD:0]				d_out,

	input	signed	[`WDP*2-1:0]			p_in,
	output	reg	signed	[`WDP*2-1:0]		p_out
	);

	// ---- stationary weight -------------------------------------------------
	reg		[`WD:0]		w;
	always @(`CLK_RST_EDGE)
		if (`RST)			w <= 0;
		else if (w_ld)		w <= w_in;

	// ---- data path: two register stages ------------------------------------
	reg	signed	[`WD:0]	d_mid;
	always @(`CLK_RST_EDGE)
		if (`RST) begin
			d_mid <= 0;
			d_out <= 0;
		end else if (en) begin
			d_mid <= d_in;
			d_out <= d_mid;
		end

	// ---- partial sum: one register stage -----------------------------------
	// Multiplies d_in, not d_mid: the tap belonging to this PE is the value
	// arriving now, while d_mid/d_out only exist to hand the sample onward.
	always @(`CLK_RST_EDGE)
		if (`RST)			p_out <= 0;
		else if (en)		p_out <= p_in + $signed(d_in) * $signed(w);

endmodule


//=============================================================================
// systolic_row -- K processing elements chained into one kernel row
//
// Emits, every cycle once the pipeline has filled, the dot product of one
// kernel row against the K pixels ending at the sample that entered K cycles
// ago.  Feed it a raster pixel stream; it needs no addressing logic at all.
//=============================================================================
module systolic_row #(
	parameter K = 5
	)(
	input									clk,
	input									rstn,
	input									en,
	// One load enable per PE.  The weight ROM presents one tap at a time, so
	// each PE latches on its own cycle -- a single shared w_ld would give every
	// PE in the row the same tap.
	input			[0:K-1]					w_ld,
	input			[`WDP*K-1:0]			w_in,
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
