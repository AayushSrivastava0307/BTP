# run_power.tcl -- power and energy per digit for one design on the Nexys 4 DDR
# (XC7A100T-1CSG324C), using switching activity from a real simulation.
#
# From the Vivado Tcl Shell, in this folder:
#     vivado -mode batch -source run_power.tcl -tclargs <design> [period_ns] [frames]
#
#   design     baseline    baseline (noc/baseline, = the original LeNet)
#              noc         NoC design (noc/): activation NoC + streaming pooling + systolic MACs
#              noc_bypass  the same NoC design with the NoC taken out (activation_noc_bypass.v)
#              ours        our systolic/ build (conv1 systolic in 2 passes, fc2 x12, MUL_PIPE)
#   period_ns  clock period, default 10 (100 MHz). Use the same value for every design.
#   frames     digits simulated for the activity file, default 10 (1..50)
#
# Steps, all automatic:
#   1. xsim runs <frames> digits through the RTL and writes activity.saif (which nets toggle
#      and how often). The testbench checks every prediction against the known answers.
#   2. synth + place + route, out of context (logic only, no I/O pins), same options as
#      ../systolic/run_vivado.tcl.
#   3. read_saif + report_power. Energy per digit = power x (clocks per digit x period).
# Output: out_<design>_<period>ns/ (reports and logs), plus one line appended to results.csv.

set part xc7a100tcsg324-1
set designs {baseline noc noc_bypass ours}
if {$argc < 1 || [lsearch -exact $designs [lindex $argv 0]] < 0} {
    puts "usage: vivado -mode batch -source run_power.tcl -tclargs <[join $designs |]> \[period_ns\] \[frames\]"
    exit 1
}
set design [lindex $argv 0]
set period 10.000
if {$argc >= 2} { set period [lindex $argv 1] }
set frames 10
if {$argc >= 3} { set frames [lindex $argv 2] }

set here [file normalize [file dirname [info script]]]
set root [file normalize [file join $here ..]]
set noc_base    [file join $root noc baseline]
set noc_dir     [file join $root noc]
set sys         [file join $root systolic]
# all four use the block-RAM ROM file (same contents as lenet_roms.v, checked word by word)
set roms        [file join $sys lenet_roms_bram.v]

# ---- which files make up each design -------------------------------------------------
set tbdef ""
switch $design {
    baseline {
        set top lenet
        set files [list global.v bhv_1w1r_sram.v bhvsrams.v cnn.v lenet.v]
        set srcdir $noc_base
        set extra  [list $roms]
    }
    noc {
        set top lenet_noc
        set tbdef DUT_NOC
        set files [list global.v bhv_1w1r_sram.v bhvsrams.v cnn.v systolic_array.v \
                        streaming_pool.v activation_noc.v lenet_noc.v]
        set srcdir $noc_dir
        set extra  [list $roms]
    }
    noc_bypass {
        set top lenet_noc
        set tbdef DUT_NOC
        set files [list global.v bhv_1w1r_sram.v bhvsrams.v cnn.v systolic_array.v \
                        streaming_pool.v lenet_noc.v]
        set srcdir $noc_dir
        set extra  [list $roms [file join $here activation_noc_bypass.v]]
    }
    ours {
        set top lenet
        set files [list global.v bhv_1p_sram.v bhv_1w1r_sram.v bhv_1w1r_sram_wp.v bhvsrams.v \
                        cnn.v pe.v linebuf.v systolic_conv.v systolic_conv2.v \
                        fc2_par_rom.v fc2_par.v lenet_roms_bram.v lenet.v]
        set srcdir $sys
        set extra  {}
    }
}

# ---- copy everything into one flat folder, so no path (or space in a path) reaches the
#      simulator's command line, and every design sees only its own global.v ------------
set out [file join $here out_${design}_${period}ns]
file delete -force $out
file mkdir [file join $out src] [file join $out sim]
set src [file join $out src]
set rtl {}
foreach f $files {
    file copy -force [file join $srcdir $f] $src
    lappend rtl $f
}
foreach f $extra {
    file copy -force $f $src
    lappend rtl [file tail $f]
}
file copy -force [file join $here tb_power.v] $src
file copy -force [file join $here test_900.yuv] [file join $out sim]

# ---- 1. simulation -> activity.saif ---------------------------------------------------
set bin [file join $::env(XILINX_VIVADO) bin]
set is_win [string equal $::tcl_platform(platform) windows]
proc tool {name args} {
    global bin is_win
    if {$is_win} {
        set cmd [list cmd /c [file nativename [file join $bin $name.bat]]]
    } else {
        set cmd [list [file join $bin $name]]
    }
    puts "  $name ..."
    # console output goes to <name>_console.txt; the tool also writes its own <name>.log
    if {[catch {exec {*}$cmd {*}$args >& ${name}_console.txt} err]} {
        puts "ERROR: $name failed. See [file join [pwd] ${name}_console.txt]"
        exit 1
    }
}

puts "== 1/3 $design: simulating $frames digits at $period ns for switching activity"
cd [file join $out sim]
# Settings go in a header, not on the command line: xvlog/xelab/xsim are .bat files on
# Windows, and a .bat splits its arguments at '=' (so -d PERIOD_NS=10 broke apart).
set fh [open [file join $src tb_settings.vh] w]
puts $fh "`define PERIOD_NS $period"
puts $fh "`define FRAMES $frames"
if {$tbdef ne ""} { puts $fh "`define $tbdef" }
close $fh
set defs [list -d FPGA_0_XILINX]
set simfiles {}
foreach f [concat $rtl tb_power.v] { lappend simfiles ../src/$f }
tool xvlog -sv -i ../src {*}$defs {*}$simfiles
tool xelab -debug typical -s pwr work.tb_power
set fh [open saif.tcl w]
puts $fh "open_saif activity.saif"
puts $fh "log_saif \[get_objects -r /tb_power/dut/*\]"
puts $fh "run -all"
puts $fh "close_saif"
puts $fh "quit"
close $fh
tool xsim pwr -tclbatch saif.tcl

if {![file exists frames.txt] || ![file exists activity.saif]} {
    puts "ERROR: simulation did not finish. See [file join [pwd] xsim.log]"
    exit 1
}
set fh [open frames.txt r]; set line [gets $fh]; close $fh
regexp {cycles_per_frame (\d+) mismatches (\d+)} $line -> cpf mism
puts "  $line"
if {$mism != 0} {
    puts "ERROR: $mism predictions differ from the known answers; not using this run."
    exit 1
}

# ---- 2. synthesis, place, route -----------------------------------------------------
puts "== 2/3 $design: synthesis and implementation (out of context, $period ns)"
cd $src
set synfiles {}
foreach f $rtl { lappend synfiles [file join $src $f] }
read_verilog -sv $synfiles
set xdc [file join $out clock.xdc]
set fh [open $xdc w]
puts $fh "create_clock -name clk -period $period \[get_ports clk\]"
close $fh
read_xdc -mode out_of_context $xdc
synth_design -top $top -part $part -mode out_of_context -retiming \
             -verilog_define FPGA_0_XILINX -include_dirs $src
opt_design
place_design
route_design
report_utilization    -file [file join $out utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 2 -file [file join $out utilization_hier.rpt]
report_timing_summary -file [file join $out timing.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]

# ---- 3. power with the simulated activity --------------------------------------------
puts "== 3/3 $design: report_power with activity.saif"
read_saif -strip_path tb_power/dut [file join $out sim activity.saif]
report_power -hierarchical_depth 3 -file [file join $out power.rpt]
set fh [open [file join $out power.rpt] r]; set rpt [read $fh]; close $fh

proc grab {pattern text} {
    if {[regexp $pattern $text -> v]} { return $v }
    return "?"
}
set p_total  [grab {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $rpt]
set p_dyn    [grab {Dynamic \(W\)\s*\|\s*([0-9.]+)} $rpt]
set p_static [grab {Device Static \(W\)\s*\|\s*([0-9.]+)} $rpt]
set conf     [grab {Confidence Level\s*\|\s*(\w+)} $rpt]
set matched  [string map {, ;} [grab {Design Nets Matched\s*\|\s*([^|]*?)\s*\|} $rpt]]

set t_us [expr {$cpf * $period / 1000.0}]
if {[string is double -strict $p_total] && [string is double -strict $p_dyn]} {
    set e_total [format %.3f [expr {$p_total * $t_us}]]
    set e_dyn   [format %.3f [expr {$p_dyn * $t_us}]]
} else {
    set e_total ?; set e_dyn ?
}

set csv [file join $here results.csv]
set new [expr {![file exists $csv]}]
set fh [open $csv a]
if {$new} {
    puts $fh "design,period_ns,wns_ns,clocks_per_digit,time_per_digit_us,total_W,dynamic_W,static_W,energy_per_digit_uJ,dynamic_energy_per_digit_uJ,confidence,nets_matched"
}
puts $fh "$design,$period,$wns,$cpf,[format %.2f $t_us],$p_total,$p_dyn,$p_static,$e_total,$e_dyn,$conf,$matched"
close $fh

puts ""
puts "=================================================================="
puts " Design            : $design (top $top)"
puts " Clock             : $period ns    WNS $wns ns (>= 0 means timing met)"
puts " Clocks per digit  : $cpf  ->  [format %.2f $t_us] us per digit"
puts " Power             : total $p_total W = dynamic $p_dyn W + static $p_static W"
puts " Energy per digit  : $e_total uJ total, $e_dyn uJ dynamic"
puts " Activity source   : simulation SAIF, confidence $conf, nets matched $matched"
puts " Reports           : $out"
puts " Added a line to   : $csv"
puts "=================================================================="
