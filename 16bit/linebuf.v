`include "global.v"

//=============================================================================
// linebuf -- sliding-window line buffer
//
// Converts a raster pixel stream into the K vertical taps of a KxK window.
//
// The baseline design re-reads the source SRAM once per kernel tap, so a 5x5
// kernel costs 25 reads per output pixel and every pixel is fetched ~25 times
// over.  This module reads each pixel exactly ONCE and holds the K-1 rows that
// are still needed, which is the entire reason a systolic array is worth
// building: compute scales with the number of PEs, memory traffic does not.
//
// Only the vertical dimension lives here.  The horizontal K comes free from
// the systolic chain in pe.v, where the pixel marches PE to PE -- so this is
// K-1 row delays, not a full KxK register file.
//
//   tap[K-1] = the incoming pixel            (bottom row of the window)
//   tap[K-2] = that pixel delayed WIDTH      (one row up)
//   ...
//   tap[0]   = delayed (K-1)*WIDTH           (top row of the window)
//
// On Xilinx the row delays map onto SRL16/SRL32 LUT shift registers rather
// than flip-flops, so the cost is far lower than the raw bit count suggests.
//=============================================================================
module linebuf #(
	parameter K     = 5,	// kernel size
	parameter WIDTH = 32,	// input plane width, in pixels
	parameter NCH   = 1		// input channels, carried side by side
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

			// bottom row of the window is simply the pixel arriving now
			assign tap[K-1][c] = din_ch[c];

			for (r = 0; r < K-1; r = r + 1) begin : gen_row
				// one row of delay: WIDTH pixels deep
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
