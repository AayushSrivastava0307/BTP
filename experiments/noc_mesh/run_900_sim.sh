#!/bin/bash
# Run 900-digit simulation in background

echo "Starting 900-digit CNN simulation..."
echo "This will take approximately 30-60 minutes..."
echo "Output will be saved to simulation_900.log"
echo ""

# Create run script for ModelSim
cat > run_sim.do << 'DOFILE'
run 500000000ns
quit -f
DOFILE

# Run simulation
vsim -c tb +nowarnTSCALE -do "run_sim.do" > simulation_900.log 2>&1 &
PID=$!

echo "Simulation started with PID: $PID"
echo "Monitor progress with: tail -f simulation_900.log"
echo "Check if running: ps aux | grep vsim"
echo ""
echo "To stop: kill $PID"
