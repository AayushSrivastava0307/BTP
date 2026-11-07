`timescale 1ns/1ps
// tb_power.v -- runs FRAMES MNIST digits back to back through one design while the simulator
// records switching activity (a SAIF file) for Vivado's report_power. The same testbench is
// used for every design, so the power numbers compare like with like.
//
// Settings come from tb_settings.vh, written by run_power.tcl next to this file:
//     PERIOD_NS   clock period in ns; must equal the clock Vivado is given
//     FRAMES      digits to run (1..50)
//     DUT_NOC     defined: top is lenet_noc (noc/); otherwise lenet
// (A header file rather than -d NAME=VALUE / plusargs: on Windows the simulator launchers
// are .bat files, which split arguments at '='.)
// Optional plusargs still override: +YUV=<file> +FRAMES=<n> +OUT=<file>.
//
// Self-check: every prediction is compared with the baseline's (all builds are bit-exact),
// so a broken compile or a mis-read input file is caught before any power number is used.
`ifndef NO_TB_SETTINGS
`include "tb_settings.vh"
`endif
`ifndef PERIOD_NS
`define PERIOD_NS 10
`endif
`ifndef FRAMES
`define FRAMES 10
`endif
module tb_power;
    reg clk = 0;
    always #(`PERIOD_NS / 2.0) clk = ~clk;

    reg         rstn = 0, go = 0;
    reg  [15:0] pixels [0:1023];
    reg  [15:0] pixel = 0;
    wire [9:0]  addr;
    wire        cena, ready;
    wire [3:0]  digit;
`ifdef DUT_NOC
    lenet_noc dut (.clk(clk), .rstn(rstn), .go(go), .cena_src(cena), .aa_src(addr),
                   .qa_src(pixel), .digit(digit), .ready(ready));
`else
    lenet     dut (.clk(clk), .rstn(rstn), .go(go), .cena_src(cena), .aa_src(addr),
                   .qa_src(pixel), .digit(digit), .ready(ready));
`endif
    always @(posedge clk) if (!cena) pixel <= pixels[addr];

    integer cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;

    // first 50 predictions of every build (baseline, NoC, NoC-bypass, systolic: bit-exact)
    localparam [8*50-1:0] EXPECT = "72104149590690159734966540740131347271211742351244";

    integer frames, f, j, fd, fo, value, started, total, errors;
    reg [8*512-1:0] yuv, outf;
    initial begin
        if (!$value$plusargs("FRAMES=%d", frames)) frames = `FRAMES;
        if (!$value$plusargs("YUV=%s", yuv)) yuv = "test_900.yuv";
        if (!$value$plusargs("OUT=%s", outf)) outf = "frames.txt";
        if (frames < 1 || frames > 50) begin $display("FRAMES must be 1..50"); $fatal(1); end
        fd = $fopen(yuv, "rb");
        if (fd == 0) begin $display("ERROR cannot open %0s", yuv); $fatal(1); end
        total = 0; errors = 0;
        repeat (10) @(negedge clk);
        rstn = 1;
        repeat (2) @(negedge clk);
        for (f = 0; f < frames; f = f + 1) begin
            for (j = 0; j < 1024; j = j + 1) begin
                value = $fgetc(fd);
                pixels[j] = value;
            end
            go = 1; started = cycles;
            @(negedge clk); go = 0;
            while (!ready) @(negedge clk);
            total = total + (cycles - started);
            if (digit != EXPECT[8*(49-f) +: 8] - "0") errors = errors + 1;
            $display("frame %0d digit %0d cycles %0d", f, digit, cycles - started);
        end
        $fclose(fd);
        fo = $fopen(outf, "w");
        $fdisplay(fo, "frames %0d total_cycles %0d cycles_per_frame %0d mismatches %0d",
                  frames, total, total / frames, errors);
        $fclose(fo);
        $display("POWER_TB frames %0d cycles_per_frame %0d mismatches %0d", frames, total / frames, errors);
`ifdef XILINX_SIMULATOR
        $stop;      // xsim: hand control back to saif.tcl so it can close the SAIF file
`else
        $finish;
`endif
    end
endmodule
