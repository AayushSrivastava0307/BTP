# run_vivado.tcl -- synthesise + place + route the LeNet accelerator for the Nexys 4 DDR
# (XC7A100T-1CSG324C) at a 5 ns / 200 MHz clock, and write utilisation and timing reports.
#
# From the "Vivado Tcl Shell" (Start menu), in this folder:
#     vivado -mode batch -source run_vivado.tcl
#
# Builds whatever global.v is set to (currently: conv1 systolic, conv2 original, fc2 x12).
# Out-of-context mode: no pin assignments needed, it measures the logic only.
# Results go to vivado_out/ ; the key line is printed at the end:  WNS = ... ns

set part   xc7a100tcsg324-1
set period 5.000
set here   [file normalize [file dirname [info script]]]
set out    $here/vivado_out
file mkdir $out
cd $here

set srcs {
    global.v bhv_1p_sram.v bhv_1w1r_sram.v bhv_1w1r_sram_wp.v bhvsrams.v cnn.v
    pe.v linebuf.v systolic_conv.v systolic_conv2.v
    fc2_par_rom.v fc2_par.v lenet_roms.v lenet.v
}
read_verilog -sv $srcs

# clock constraint
set xdc $out/clock.xdc
set f [open $xdc w]
puts $f "create_clock -name clk -period $period \[get_ports clk\]"
close $f
read_xdc -mode out_of_context $xdc

synth_design -top lenet -part $part -mode out_of_context \
             -verilog_define FPGA_0_XILINX -include_dirs $here
report_utilization    -file $out/utilization_synth.rpt
report_timing_summary -file $out/timing_synth.rpt

opt_design
place_design
route_design
report_utilization    -file $out/utilization_routed.rpt
report_timing_summary -file $out/timing_routed.rpt -max_paths 10
report_timing -sort_by group -max_paths 10 -file $out/worst_paths.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts ""
puts "=================================================================="
puts " Clock target : $period ns ([expr {1000.0/$period}] MHz)"
puts " WNS          : $wns ns   (>= 0 means timing is met)"
if {$wns < 0} {
    puts " Fastest clock that works now: about [format %.2f [expr {$period - $wns}]] ns"
}
puts " Reports      : $out"
puts "=================================================================="
