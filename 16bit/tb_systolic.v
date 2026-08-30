`include "global.v"

//=============================================================================
// tb_systolic -- unit tests for pe / systolic_row / linebuf
//
// Run with:  vsim -c -do run_unit.do
//
// These are checked against an independent golden model written in plain
// behavioural code, so a mistake in the RTL timing cannot hide behind a
// matching mistake in the expected values.
//=============================================================================
module tb_systolic();

	localparam K     = 5;
	localparam WIDTH = 8;

	reg		clk = 0;
	reg		rstn = 0;
	always #5 clk = ~clk;

	integer	errors = 0;
	integer	checks = 0;

	//=========================================================================
	// Test 1 -- systolic_row against a golden FIR
	//=========================================================================
	reg					row_en   = 0;
	reg		[0:K-1]		row_w_ld = 0;	// one load enable per PE
	reg		[`WDP*K-1:0]	row_w;
	reg	signed	[`WD:0]		row_d = 0;
	wire signed	[`WDP*2-1:0] row_q;

	systolic_row #(.K(K)) dut_row(
		.clk	(clk),
		.rstn	(rstn),
		.en		(row_en),
		.w_ld	(row_w_ld),
		.w_in	(row_w),
		.d_in	(row_d),
		.p_out	(row_q)
		);

	// golden model state
	integer	xh	[0:255];		// pixel history, indexed by cycle
	integer	wg	[0:K-1];
	integer	n;					// cycle counter

	function integer golden_row (input integer cyc);
		integer m, acc, idx;
		begin
			acc = 0;
			for (m = 0; m < K; m = m + 1) begin
				idx = cyc - (K-1) - m;
				if (idx >= 0) acc = acc + wg[m] * xh[idx];
			end
			golden_row = acc;
		end
	endfunction

	//=========================================================================
	// Test 2 -- linebuf vertical taps
	//=========================================================================
	reg						lb_en  = 0;
	reg						lb_clr = 0;
	reg		[`WDP-1:0]		lb_d   = 0;
	wire	[`WDP*K-1:0]	lb_q;
	wire	[0:K-1][`WD:0]	lb_tap = lb_q;

	linebuf #(.K(K), .WIDTH(WIDTH), .NCH(1)) dut_lb(
		.clk	(clk),
		.rstn	(rstn),
		.en		(lb_en),
		.clr	(lb_clr),
		.d_in	(lb_d),
		.d_out	(lb_q)
		);

	//=========================================================================
	// stimulus
	//=========================================================================
	integer	i, r, expect_v, got_v, expect_tap;

	initial begin
		for (i = 0; i < 256; i = i + 1) xh[i] = 0;

		// kernel taps as loaded: w[0] multiplies the NEWEST sample
		wg[0] = 1; wg[1] = 2; wg[2] = 3; wg[3] = 4; wg[4] = 5;
		row_w = {16'sd1, 16'sd2, 16'sd3, 16'sd4, 16'sd5};

		rstn = 0;
		repeat (3) @(negedge clk);
		rstn = 1;
		@(negedge clk);

		// ---- load the stationary weights --------------------------------
		// row_w carries all K taps at once here, so every PE latches together
		row_w_ld = {K{1'b1}};
		@(negedge clk);
		row_w_ld = 0;
		@(negedge clk);

		$display("");
		$display("=== Test 1: systolic_row (K=%0d) ===", K);

		row_en = 1;
		lb_en  = 1;
		n = 0;

		for (i = 1; i <= 40; i = i + 1) begin
			// drive sample x(n) = i during cycle n
			row_d   = i;
			lb_d    = i;
			xh[n]   = i;

			@(posedge clk);
			#1;						// let the registers settle

			expect_v = golden_row(n);
			got_v    = $signed(row_q);
			checks   = checks + 1;
			if (expect_v !== got_v) begin
				errors = errors + 1;
				$display("  FAIL cycle %0d: row_q = %0d, expected %0d",
				         n, got_v, expect_v);
			end

			@(negedge clk);
			n = n + 1;
		end
		$display("  systolic_row: %0d cycles checked", 40);

		// ---- linebuf ----------------------------------------------------
		$display("");
		$display("=== Test 2: linebuf (K=%0d, WIDTH=%0d) ===", K, WIDTH);

		// keep streaming; taps are checked combinationally during each cycle
		for (i = 41; i <= 90; i = i + 1) begin
			lb_d  = i;
			row_d = i;
			xh[n] = i;

			#1;						// settle the combinational tap
			for (r = 0; r < K; r = r + 1) begin
				// tap[K-1] is the pixel arriving now; each row up is WIDTH older
				expect_tap = (n - (K-1-r)*WIDTH >= 0) ? xh[n - (K-1-r)*WIDTH] : 0;
				checks = checks + 1;
				if (lb_tap[r] !== expect_tap[`WD:0]) begin
					errors = errors + 1;
					$display("  FAIL cycle %0d tap[%0d] = %0d, expected %0d",
					         n, r, lb_tap[r], expect_tap);
				end
			end

			@(posedge clk);
			@(negedge clk);
			n = n + 1;
		end
		$display("  linebuf: %0d cycles checked", 50);

		//=====================================================================
		$display("");
		$display("=====================================");
		if (errors == 0)
			$display("  ALL PASS  (%0d checks)", checks);
		else
			$display("  %0d FAILURES out of %0d checks", errors, checks);
		$display("=====================================");
		$display("");
		$finish();
	end

endmodule
