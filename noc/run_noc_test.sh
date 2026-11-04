#!/bin/bash
# Quick NoC test runner

echo "Compiling NoC test..."
vlib work
vlog -sv global.v
vlog -sv noc_router.v
vlog -sv noc_mesh.v
vlog -sv noc_simple_test.v

echo ""
echo "Running NoC routing test..."
vsim -c noc_simple_test -do "run -all; quit"

echo ""
echo "Test complete!"
