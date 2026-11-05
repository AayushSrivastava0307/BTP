`include "global.v"
// tb_fc2_par -- runs the original fc2 path (iterator + conv + wieght_fc2_rom/bias_fc2_rom)
// and fc2_par on the same 120 inputs, and checks that all 84 outputs match bit for bit,
// in the same order.  Several input sets: random, all-max, all-zero, sparse.
module tb_fc2_par;
	reg clk = 0, rstn = 0;
	always #2.5 clk = ~clk;

	// the input buffer both engines read (stands in for relu_fc1_buf)
	reg [15:0] xmem [0:127];

	// ---- original path ----
	reg go = 0;
	wire [13:0] aa_w_o; wire [`W_OUPTUT_BATCH:0] aa_b_o; wire [15:0] aa_d_o; wire cena_o;
	wire first_o, last_o, ready_o;
	iterator #(.OUTPUT_BATCH(`OUTPUT_BATCH_FC2), .KERNEL_SIZEX(`KERNEL_SIZEX_FC2), .KERNEL_SIZEY(`KERNEL_SIZEY_FC2),
	           .STEP(1), .INPUT_WIDTH(`INPUT_WIDTH_FC2), .INPUT_HEIGHT(`INPUT_HEIGHT_FC2))
		it (.clk(clk), .rstn(rstn), .go(go), .first_data(first_o), .last_data(last_o), .aa_bias(aa_b_o),
		    .aa_data(aa_d_o), .aa_weight(aa_w_o), .cena(cena_o), .ready(ready_o));
	wire [15:0] w_o; wire [23:0] b_o;
	wieght_fc2_rom wr (.clk(clk), .rstn(rstn), .aa(aa_w_o), .cena(cena_o), .qa(w_o));
	bias_fc2_rom   br (.clk(clk), .rstn(rstn), .aa(aa_b_o), .cena(cena_o), .qa(b_o));
	reg [15:0] x_o;
	always @(posedge clk) if (!cena_o) x_o <= xmem[aa_d_o[6:0]];
	reg [15:0] cena_d, first_d, last_d;
	always @(*) begin cena_d[0] = cena_o; first_d[0] = first_o; last_d[0] = last_o; end
	always @(posedge clk) if (!rstn) begin cena_d[15:1] <= 0; first_d[15:1] <= 0; last_d[15:1] <= 0; end
	                      else begin cena_d[15:1] <= cena_d; first_d[15:1] <= first_d; last_d[15:1] <= last_d; end
	wire [15:0] q_o; wire q_en_o;
	conv #(.INPUT_NUM(1), .OUTPUT_NUM(1), .WIGHT_SHIFT(`WIGHT_SHIFT))
		cv (.clk(clk), .rstn(rstn), .en(~cena_d[1]), .first_data(first_d[1]), .last_data(last_d[1]),
		    .data_i(x_o), .bias(b_o), .weight(w_o), .q(q_o), .q_en(q_en_o));

	// ---- parallel path ----
	wire [6:0] aa_p; wire cena_p; reg [15:0] x_p;
	always @(posedge clk) if (!cena_p) x_p <= xmem[aa_p];
	wire [15:0] q_p; wire q_en_p, ready_p;
	fc2_par #(.P(12)) dut (.clk(clk), .rstn(rstn), .go(go), .aa_data(aa_p), .cena_data(cena_p), .qa_data(x_p),
	                       .q_en(q_en_p), .q(q_p), .ready(ready_p));

	// ---- collect ----
	reg [15:0] out_o [0:127], out_p [0:127];
	integer n_o, n_p, t_go, t_rdy_o, t_rdy_p, cyc;
	always @(posedge clk) cyc <= cyc + 1;
	always @(posedge clk) if (q_en_o) begin out_o[n_o] <= q_o; n_o <= n_o + 1; end
	always @(posedge clk) if (q_en_p) begin out_p[n_p] <= q_p; n_p <= n_p + 1; end
	always @(posedge clk) if (ready_o) t_rdy_o <= cyc;
	always @(posedge clk) if (ready_p) t_rdy_p <= cyc;

	integer set, i, errs, total_errs, seed;
	task run_set(input integer s);
		begin
			n_o = 0; n_p = 0; t_rdy_o = -1; t_rdy_p = -1;
			@(posedge clk); go <= 1; t_go = cyc; @(posedge clk); go <= 0;
			wait (t_rdy_o >= 0 && t_rdy_p >= 0);
			repeat (40) @(posedge clk);
			errs = 0;
			if (n_o != 84 || n_p != 84) begin
				$display("set %0d: COUNT MISMATCH original %0d, parallel %0d", s, n_o, n_p); errs = errs + 1;
			end
			for (i = 0; i < 84; i = i + 1)
				if (out_o[i] !== out_p[i]) begin
					if (errs < 5) $display("set %0d: neuron %0d original %h parallel %h", s, i, out_o[i], out_p[i]);
					errs = errs + 1;
				end
			$display("set %0d: %0d/84 identical | original ready after %0d clocks, parallel %0d clocks",
			         s, 84 - errs, t_rdy_o - t_go, t_rdy_p - t_go);
			total_errs = total_errs + errs;
		end
	endtask

	initial begin
		cyc = 0; total_errs = 0; seed = 7;
		repeat (10) @(posedge clk); rstn = 1; repeat (5) @(posedge clk);
		for (set = 0; set < 8; set = set + 1) begin
			for (i = 0; i < 128; i = i + 1)
				case (set)
					0: xmem[i] = 16'h7fff;                                  // every input at max
					1: xmem[i] = 0;                                         // all zero -> bias only
					2: xmem[i] = (i % 7 == 0) ? ($random(seed) & 16'h7fff) : 0;  // sparse, like ReLU output
					default: xmem[i] = $random(seed) & 16'h7fff;            // relu outputs are >= 0
				endcase
			run_set(set);
		end
		// one set with negative inputs too, to exercise sign handling
		for (i = 0; i < 128; i = i + 1) xmem[i] = $random(seed);
		run_set(8);
		if (total_errs == 0) $display("PASS: all sets bit-identical");
		else                 $display("FAIL: %0d mismatches", total_errs);
		$finish;
	end
endmodule
