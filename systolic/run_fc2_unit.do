#==============================================================================
# run_fc2_unit.do -- checks fc2_par against the original fc2 path, bit for bit
#
#   vsim -c -do run_fc2_unit.do
#
# Runs the original iterator + conv + wieght_fc2_rom/bias_fc2_rom and fc2_par on the
# same 120 inputs (9 sets: random, all-max, all-zero, sparse, signed) and compares all
# 84 outputs in order.  Expect "PASS: all sets bit-identical" and
# "original ready after 10082 clocks, parallel 863 clocks".
#==============================================================================
if {[batch_mode]} { onerror {quit -f -code 1} }
catch {quit -sim}
if {[file isdirectory work_fc2]} { vdel -all -lib work_fc2 }
vlib work_fc2
vmap work_fc2 work_fc2
vlog -sv -work work_fc2 -timescale=1ns/1ps \
    global.v cnn.v lenet_roms.v fc2_par_rom.v fc2_par.v tb_fc2_par.v
vsim -c work_fc2.tb_fc2_par
run -all
if {[batch_mode]} { quit -f }
