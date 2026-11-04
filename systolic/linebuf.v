`include "global.v"

// Turns a raster pixel stream into the K vertical taps of a KxK window, so
// each pixel is read from the source SRAM once instead of once per kernel tap.
//
// Vertical dimension only -- the horizontal K comes from the pixel marching PE
// to PE in pe.v, so this is K-1 row delays, not a KxK register file.
//
//   tap[K-1] = incoming pixel        (bottom row)
//   tap[K-2] = delayed WIDTH         (one row up)
//   tap[0]   = delayed (K-1)*WIDTH   (top row)
//
// The row delays map to SRL16/SRL32 LUT shift registers on Xilinx.
module linebuf #(
	parameter K     = 5,
	parameter WIDTH = 32,	// input plane width, in pixels
	parameter NCH   = 1
	)(
	input									clk,
	input									rstn,
	input									en,		// advance one pixel
	input									clr,	// flush between frames
	input			[`WDP*NCH-1:0]			d_in,
	output			[`WDP*NCH*K-1:0]		d_out	// [row][channel], row 0 = top
	);

	wire	[0:NCH-1][`WD:0]			din_ch = d_in;
	wire	[0:K-1][0:NCH-1][`WD:0]		tap;

	genvar c, r;
	generate
		for (c = 0; c < NCH; c = c + 1) begin : gen_ch

			assign tap[K-1][c] = din_ch[c];

			for (r = 0; r < K-1; r = r + 1) begin : gen_row
				reg	[0:WIDTH-1][`WD:0]	sr;
				always @(`CLK_RST_EDGE)
					if (`RST)		sr <= 0;
					else if (clr)	sr <= 0;
					else if (en)	sr <= {tap[K-1-r][c], sr[0:WIDTH-2]};

				assign tap[K-2-r][c] = sr[WIDTH-1];
			end
		end
	endgenerate

	assign d_out = tap;

endmodule
