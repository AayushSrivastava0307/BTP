#==============================================================================
# run.do -- compile and simulate the 16-bit LeNet-5 in ModelSim
#
#   Batch (no GUI) :  sim.bat            <- easiest, just double-click
#   Batch (manual) :  vsim -c -l result.log -do run.do
#   GUI            :  do run.do
#
# The design needs ./test_900f.yuv as stimulus.  If it is missing, generate it
# with:   python png_to_yuv.py       (reads test_900.png, writes 900 frames)
#
# Predictions land in the transcript as
#     T<time>==process a frame <n>, digit <d>
# score.py parses that and compares against the MNIST test labels.
#==============================================================================

# ---- stimulus check -------------------------------------------------------
if {![file exists test_900f.yuv]} {
    echo "ERROR: test_900f.yuv not found.  Run:  python png_to_yuv.py"
    if {[batch_mode]} { quit -f -code 1 }
    return
}

# ---- abort the script on any compile/elab error when running headless -----
if {[batch_mode]} { onerror {quit -f -code 1} }

# ---- clean library so a stale .qdb can never mask a source edit -----------
# 'quit -sim' errors if nothing is loaded, which is the normal case here.
# Library name; override to run a second simulation alongside a first, e.g.
#     vsim -c -do "set LIB work_sys; do run.do"
if {![info exists LIB]} { set LIB work }

catch {quit -sim}
if {[file isdirectory $LIB]} { vdel -all -lib $LIB }

vlib $LIB
vmap $LIB $LIB

# ---- compile --------------------------------------------------------------
# Order matches the original flow; global.v is `include-d by the others but is
# listed anyway so that editing it always forces a recompile.
# pe.v / linebuf.v / systolic_conv.v are the systolic path, selected by the
# SYSTOLIC_CONV1 switch in global.v.
vlog -sv -work $LIB -timescale=1ns/1ps \
    bhv_1p_sram.v      \
    bhv_1w1r_sram.v    \
    bhv_1w1r_sram_wp.v \
    bhvsrams.v         \
    cnn.v              \
    global.v           \
    pe.v               \
    linebuf.v          \
    systolic_conv.v    \
    systolic_conv2.v   \
    lenet.v            \
    lenet_roms.v       \
    lenet_tb.v

# ---- elaborate and run ----------------------------------------------------
# Set NFRAMES before sourcing to shorten the run, e.g.
#     vsim -c -do "set NFRAMES 20; do run.do"
# Left unset, the testbench classifies all 900 frames.
set plusargs ""
if {[info exists NFRAMES]} {
    set plusargs "+NFRAMES=$NFRAMES"
    echo "run.do: limiting run to $NFRAMES frames"
}

eval vsim -voptargs=+acc $plusargs $LIB.tb

run -all

if {[batch_mode]} { quit -f }
