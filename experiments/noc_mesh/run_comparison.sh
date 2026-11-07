#!/bin/bash
# Quick comparison script for CNN designs

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          CNN DESIGN PERFORMANCE COMPARISON TOOL                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if conda environment exists
if ! conda env list | grep -q "cnn_analysis"; then
    echo "⚠️  Environment 'cnn_analysis' not found. Creating..."
    conda create -n cnn_analysis python=3.10 -y
    source /home/arjun/miniconda3/etc/profile.d/conda.sh
    conda activate cnn_analysis
    pip install matplotlib numpy pandas seaborn
    echo "✅ Environment created successfully!"
else
    echo "✅ Environment 'cnn_analysis' found"
fi

# Activate environment
source /home/arjun/miniconda3/etc/profile.d/conda.sh
conda activate cnn_analysis

echo ""
echo "🔍 Checking for simulation results..."

# Check for enhanced design results
if [ -f "results_900.log" ]; then
    echo "✅ Found enhanced design results: results_900.log"
    ENHANCED_LOG="--enhanced-log results_900.log"
else
    echo "⚠️  Enhanced design log not found, using default metrics"
    ENHANCED_LOG=""
fi

# Check for original design results
if [ -f "original_results.log" ]; then
    echo "✅ Found original design results: original_results.log"
    ORIGINAL_LOG="--original-log original_results.log"
else
    echo "ℹ️  Original design log not found, using default baseline"
    ORIGINAL_LOG=""
fi

echo ""
echo "📊 Running comparison analysis..."
python compare_designs.py $ORIGINAL_LOG $ENHANCED_LOG

# Check if plots were generated
if [ -f "speedup_comparison.png" ] && [ -f "detailed_speedup.png" ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ COMPARISON COMPLETE!                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📁 Generated Files:"
    echo "   1. speedup_comparison.png       (878 KB - 9-panel view)"
    echo "   2. detailed_speedup.png         (448 KB - 4-panel analysis)"
    echo "   3. architecture_comparison.png  (354 KB - architecture diagrams)"
    echo "   4. performance_report.txt       (2.3 KB - text summary)"
    echo ""
    echo "📈 Key Results:"
    grep -A 2 "Throughput Speedup:" performance_report.txt
    grep -A 2 "Energy Efficiency:" performance_report.txt
    echo ""
    echo "📖 To view results:"
    echo "   Text:   cat performance_report.txt"
    echo "   Images: eog speedup_comparison.png"
    echo ""
    echo "📚 For more details, see: COMPARISON_TOOL_README.md"
    echo ""
else
    echo ""
    echo "⚠️  Some output files are missing. Check for errors above."
fi
