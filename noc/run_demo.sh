#!/bin/bash
echo "=========================================="
echo "CNN with NoC - Processing 50 Digits Demo"
echo "=========================================="
echo ""
echo "Starting simulation..."
timeout 600 vsim -c tb +nowarnTSCALE -do "run -all; quit" 2>&1 | tee demo_output.log
echo ""
echo "Demo complete! Check demo_output.log for full results"
