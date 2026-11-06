#!/bin/bash
# run_verilator.sh [NFRAMES] -- fast full-network simulation with Verilator (Linux or WSL).
#
# Builds the design in ../ exactly as configured in ../global.v, runs NFRAMES digits
# (default 900) and scores them.  900 frames take a few seconds instead of ModelSim's hour.
# Needs: verilator 5.x (pip install verilator), g++ >= 10, python3 with numpy + Pillow.
#
# Uses lenet_roms_bram.v (the copy Vivado synthesises; same words as lenet_roms.v, whose
# huge packed-array initialisers are too much for Verilator).  Regenerate it with
# gen_bram_roms.py if lenet_roms.v changes.
set -e
cd "$(dirname "$0")"
N=${1:-900}
SRC=..
[ -f "$SRC/test_900f.yuv" ] || (cd "$SRC" && python3 png_to_yuv.py)
ln -sf "$SRC/test_900f.yuv" test_900f.yuv
[ -f "$SRC/lenet_roms_bram.v" ] || (cd "$SRC" && python3 gen_bram_roms.py)
VL=$(command -v verilator || echo "$(python3 -c 'import verilator,os;print(os.path.dirname(verilator.__file__))')/bin/verilator")
export VERILATOR_ROOT=${VERILATOR_ROOT:-$(dirname "$(dirname "$VL")")}
rm -rf obj
"$VL" --binary --timing -Wno-fatal -Wno-lint -Wno-style -DSIMULATING --top-module tb \
  -I"$SRC" -I. -j 2 -CFLAGS -fcoroutines -MAKEFLAGS "CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O1" --Mdir obj \
  tb_iv.v "$SRC"/global.v "$SRC"/bhv_1p_sram.v "$SRC"/bhv_1w1r_sram.v "$SRC"/bhv_1w1r_sram_wp.v \
  "$SRC"/bhvsrams.v "$SRC"/cnn.v "$SRC"/pe.v "$SRC"/linebuf.v "$SRC"/systolic_conv.v "$SRC"/systolic_conv2.v \
  "$SRC"/fc2_par_rom.v "$SRC"/fc2_par.v "$SRC"/lenet_roms_bram.v "$SRC"/lenet.v > build.log 2>&1 \
  || { grep -E "error" build.log | head; exit 1; }
./obj/Vtb +NFRAMES="$N" > result_verilator.log
grep "^L frame" result_verilator.log | tail -1
(cd "$SRC" && python3 score.py verilator/result_verilator.log)
