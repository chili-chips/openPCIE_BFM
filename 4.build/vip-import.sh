#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Import the co-simulation VIP from upstream (github.com/wyvernSemi) into
# 1.upstream/vip/, with our changes applied. Run it only to upgrade a model: set
# the pins below, run, then run the self-test on every simulator and update
# 1.upstream/vip/README.md.
#
#   bash 4.build/vip-import.sh
#
# Copies only the files the build uses, with LF line endings, then applies:
#   - pcieVHost.v: VProc's BE and Burst ports, left open (we build VProc with
#     VPROC_BYTE_ENABLE)
#   - test_defs.v: `fatal calls tb.Fatal, our test bench top
#   - pcieVHost: transaction taps, TLP and DLLP ports
#     (1.upstream/patches/pcievhost-taps.patch)
#   - pcie_vhost_map.v: generated from pcie_vhost_map.h, as upstream's make
#     files do
#   - SystemVerilog names, after the patches (they name upstream's files):
#     modules .sv, `include headers .svh, the `include lines to match
#   - READMEs: <p align="center"> blocks become <div align="center">
# pcieVHost's src/ltssm.c is not copied: the make file compiles ours,
# 3.sw/ltssm/ltssm.c, with its LTSSM patch (3.sw/ltssm/README.md).
# 1.upstream/patches/pcievhost-speed.patch and 1.upstream/patches/vproc-coroutine.patch are applied
# at build time (4.build/build-vip.sh, VIP_PATCH and VPROC_PATCH).
#
# DEPS_WORK (default ~/.cache/openPCIE_BFM-deps) holds the upstream
# clones. Needs git, patch, sed.
set -euo pipefail
VPROC_REF=${VPROC_REF:-VERSION_1_13_4}
PCIEVHOST_REF=${PCIEVHOST_REF:-VESRSION_1_9_3}   # sic: upstream's tag name
MEM_MODEL_REF=${MEM_MODEL_REF:-c7b9c62}
HERE=$(cd "$(dirname "$0")" && pwd)
D=$(cd "$HERE/.." && pwd)/1.upstream/vip
U=${DEPS_WORK:-$HOME/.cache/openPCIE_BFM-deps}
mkdir -p "$U"

fetch() {  # <repo> <ref>: clone or update, check out
  [ -d "$U/$1/.git" ] || git clone -q "https://github.com/wyvernSemi/$1.git" "$U/$1"
  git -C "$U/$1" cat-file -e "$2^{commit}" 2>/dev/null || git -C "$U/$1" fetch -q --tags origin
  git -C "$U/$1" checkout -q "$2"
}
cp_lf() {  # <src> <dst>: upstream mixes CRLF and LF; we keep LF
  mkdir -p "$(dirname "$2")"
  tr -d '\r' < "$1" > "$2"
}

fetch vproc "$VPROC_REF"
fetch pcievhost "$PCIEVHOST_REF"
fetch mem_model "$MEM_MODEL_REF"
rm -rf "$D"/{vproc,pcievhost,mem_model}

# ---- VProc --------------------------------------------------------------------
for f in VSched.c VUser.c VProc.h VProcClass.h VProcIrqClass.h VSched_pli.h VUser.h; do
  cp_lf "$U/vproc/code/$f" "$D/vproc/code/$f"
done
for f in f_VProc.v extradefs.v vprocdefs.vh vprocdpi.vh LICENSE README.md; do
  cp_lf "$U/vproc/$f" "$D/vproc/$f"
done

# ---- pcieVHost ----------------------------------------------------------------
P=$D/pcievhost
for f in "$U"/pcievhost/src/*.c "$U"/pcievhost/src/*.h; do
  [ "$(basename "$f")" = ltssm.c ] && continue   # the make file compiles 3.sw/ltssm/ltssm.c
  cp_lf "$f" "$P/src/$(basename "$f")"
done
for f in allheaders.v pciedispheader.v pciexpress_header.v timescale.v; do
  cp_lf "$U/pcievhost/verilog/headers/$f" "$P/verilog/headers/$f"
done
cp_lf "$U/pcievhost/verilog/test/test_defs.v" "$P/verilog/test/test_defs.v"
for f in pcieVHost.v pcieVHostPipex1.v; do cp_lf "$U/pcievhost/verilog/pcieVHost/$f" "$P/verilog/pcieVHost/$f"; done
for f in clkmux.v Serialiser.v; do cp_lf "$U/pcievhost/verilog/lib/$f" "$P/verilog/lib/$f"; done
for f in LICENSE README.md; do cp_lf "$U/pcievhost/$f" "$P/$f"; done

# change: `fatal calls tb.Fatal
sed -i 's/`define fatal test\.Fatal;/`define fatal tb.Fatal;/' "$P/verilog/test/test_defs.v"
grep -q 'define fatal tb\.Fatal' "$P/verilog/test/test_defs.v"

# change: VProc byte-enable and burst ports, left open
F=$P/verilog/pcieVHost/pcieVHost.v
grep -qE '^\s*\.RD\s*\(RD\),$' "$F"
sed -i -E '/^\s*\.RD\s*\(RD\),$/a\
`ifdef VPROC_BYTE_ENABLE\
           .BE             (),\
`endif\
`ifdef VPROC_BURST_IF\
           .Burst          (),\
           .BurstFirst     (),\
           .BurstLast      (),\
`endif' "$F"

# change: transaction taps, TLP and DLLP ports (0.doc/pcievhost/README.md)
patch -s --no-backup-if-mismatch -p1 -d "$P" < "$HERE/../1.upstream/patches/pcievhost-taps.patch"

# change: the register map, generated from the C header
sed "s/0x/32'h/;s/#/\`/;s/DEFINES/AUTO GENERATED. DO NOT EDIT!/;" "$P/src/pcie_vhost_map.h" \
  > "$P/verilog/headers/pcie_vhost_map.v"

# ---- mem_model (its C model is part of pcieVHost) -------------------------------
for f in mem_model.v mem_model_dpi.vh LICENSE README.md; do cp_lf "$U/mem_model/$f" "$D/mem_model/$f"; done
# no `timescale in the HDL: the simulator command line gives it
sed -i '/^`timescale/d' "$D/mem_model/mem_model.v"

# ---- SystemVerilog names: modules .sv, `include headers .svh ------------------
for f in "$D"/vproc/f_VProc.v "$P"/verilog/pcieVHost/*.v "$P"/verilog/lib/*.v; do
  mv "$f" "${f%.v}.sv"
done
mv "$D/mem_model/mem_model.v" "$D/mem_model/f_mem_model.sv"  # upstream has a mem_model.sv of its own
for f in "$D"/vproc/extradefs.v "$P"/verilog/headers/*.v "$P"/verilog/test/test_defs.v; do
  mv "$f" "${f%.v}.svh"
done
sed -i -E 's/(`include "\w+)\.v"/\1.svh"/' "$D"/vproc/vprocdefs.vh "$P"/verilog/headers/allheaders.svh \
  "$P"/verilog/lib/*.sv "$P"/verilog/pcieVHost/*.sv
if grep -rqE '`include "\w+\.v"' "$D"/vproc "$P"/verilog "$D"/mem_model; then
  echo "ERROR: an \`include of a .v file is left"; exit 1
fi


# ---- upstream READMEs: centred blocks in <div>, which GitLab also honors ---------
sed -i -e '/<p align="center">/,/<\/p>/{s#<p align="center">#<div align="center">#;s#</p>#</div>#}' \
  "$D"/{vproc,pcievhost,mem_model}/README.md

echo "imported: VProc $VPROC_REF, pcieVHost $PCIEVHOST_REF, mem_model $MEM_MODEL_REF"
echo "next: update 1.upstream/vip/README.md, then run the self-test on every simulator"

# -----------------------------------------------------------------------------
# Project:     openPCIE_BFM
# Description: PCIE simulation model on pcieVHost
# Version:     1.0
# Date:        Oct 18, 2026
# -----------------------------------------------------------------------------
