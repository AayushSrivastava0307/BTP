`include "global.v"
// tb_iv -- plain-Verilog version of lenet_tb.v for Icarus Verilog (no interface/clocking blocks).
// Same stimulus (test_900f.yuv), same frame handshake, same "process a frame" line, so
// score.py reads its log.  Also prints each layer's go->ready clock count per frame.
//     vvp tb_iv.vvp +NFRAMES=20
module tb;
	reg clk = 1, rstn = 0;
	always #(`CLK_PERIOD_DIV2) clk = ~clk;

	reg  [15:0] src [0:1023];
	wire [9:0]  aa_src;  wire cena_src;
	reg  [15:0] qa_src;
	always @(posedge clk) if (!rstn) qa_src <= 0; else if (!cena_src) qa_src <= src[aa_src];

	reg go = 0;
	wire [3:0] digit; wire ready;
	lenet lenet (.clk(clk), .rstn(rstn), .go(go), .cena_src(cena_src), .aa_src(aa_src),
	             .qa_src(qa_src), .digit(digit), .ready(ready));

	// per-layer timing: clocks from each layer's go to its ready
	integer cyc = 0;
	always @(posedge clk) cyc <= cyc + 1;
	integer t_go, t_c1, t_p1, t_c2, t_p2, t_f1, t_f2, t_f3;
	always @(posedge clk) begin
		if (lenet.conv1_go)       t_go = cyc;
		if (lenet.conv1_ready)    t_c1 = cyc;
		if (lenet.pooling1_ready) t_p1 = cyc;
		if (lenet.conv2_ready)    t_c2 = cyc;
		if (lenet.pooling2_ready) t_p2 = cyc;
		if (lenet.fc1_ready)      t_f1 = cyc;
		if (lenet.fc2_ready)      t_f2 = cyc;
		if (lenet.fc3_ready)      t_f3 = cyc;
	end

	integer nframes, f, i, fd, prev_t;
	initial begin
		if (!$value$plusargs("NFRAMES=%d", nframes)) nframes = 900;
		fd = $fopen("test_900f.yuv", "rb");
		if (fd == 0) begin $display("cannot open test_900f.yuv"); $finish; end
		#(`RESET_DELAY); rstn = 1;
		#(`RESET_DELAY);
		prev_t = -1;
		for (f = 0; f < nframes; f = f + 1) begin
			@(posedge clk); @(posedge clk);
			for (i = 0; i < 1024; i = i + 1) src[i] = $fgetc(fd);
			@(posedge clk); @(posedge clk);
			go <= 1; @(posedge clk); go <= 0;
			@(posedge clk); while (!ready) @(posedge clk);
			$display("T%d==process a frame %d, digit %d =============", $time, f, digit);
			$display("L frame %0d conv1 %0d pool1 %0d conv2 %0d pool2 %0d fc1 %0d fc2 %0d fc3 %0d total %0d interval %0d",
			         f, t_c1 - t_go, t_p1 - t_c1, t_c2 - t_p1, t_p2 - t_c2, t_f1 - t_p2, t_f2 - t_f1, t_f3 - t_f2,
			         cyc - t_go, (prev_t < 0) ? 0 : cyc - prev_t);
			prev_t = cyc;
			@(posedge clk); @(posedge clk);
		end
		$finish;
	end
endmodule
