if {[batch_mode]} { onerror {quit -f -code 1} }
catch {quit -sim}
if {[file isdirectory work_xil]} { vdel -all -lib work_xil }
vlib work_xil
vlog -sv -work work_xil -timescale=1ns/1ps +define+FPGA_0_XILINX global.v bhv_1p_sram.v bhv_1w1r_sram.v bhv_1w1r_sram_wp.v bhvsrams.v cnn.v pe.v linebuf.v systolic_conv.v systolic_conv2.v fc2_par_rom.v fc2_par.v lenet_roms.v lenet.v lenet_tb.v
vsim -voptargs=+acc -c +NFRAMES=12 work_xil.tb
run -all
if {[batch_mode]} { quit -f }
