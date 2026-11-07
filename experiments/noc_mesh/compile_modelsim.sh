#!/bin/bash
# ModelSim compilation script for CNN with NoC

# Create work library
vlib work

# Compile design files in dependency order
echo "Compiling global definitions..."
vlog -sv global.v

echo "Compiling behavioral SRAMs..."
vlog -sv bhv_1p_sram.v
vlog -sv bhv_1w1r_sram.v  
vlog -sv bhv_1w1r_sram_wp.v
vlog -sv bhvsrams.v

echo "Compiling NoC components..."
vlog -sv noc_router.v
vlog -sv noc_mesh.v

echo "Compiling systolic array..."
vlog -sv systolic_array.v

echo "Compiling CNN modules..."
vlog -sv cnn.v
vlog -sv lenet_roms.v
vlog -sv lenet.v
vlog -sv lenet_noc_simple.v

echo "Compiling testbench..."
vlog -sv lenet_tb.v

echo "Compilation complete!"
echo ""
echo "To run simulation:"
echo "  vsim -c tb -do \"run -all; quit\""
echo ""
echo "To run with GUI:"
echo "  vsim tb"
echo "  run -all"
