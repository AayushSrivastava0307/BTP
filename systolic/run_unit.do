#==============================================================================
# run_unit.do -- unit tests for the systolic building blocks
#
#   vsim -c -do run_unit.do
#
# Uses its own library (work_unit) so it can run while a full-network
# simulation is still using ./work.
#==============================================================================

if {[batch_mode]} { onerror {quit -f -code 1} }

catch {quit -sim}
if {[file isdirectory work_unit]} { vdel -all -lib work_unit }

vlib work_unit
vmap work_unit work_unit

vlog -sv -work work_unit -timescale=1ns/1ps \
    pe.v             \
    linebuf.v        \
    systolic_conv.v  \
    tb_systolic.v

vsim -voptargs=+acc work_unit.tb_systolic

run -all

if {[batch_mode]} { quit -f }
