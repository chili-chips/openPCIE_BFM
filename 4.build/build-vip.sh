#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Build the co-simulation VIP from the upstream copies in 1.upstream/vip/: VProc,
# the pcieVHost PCIE model and mem_model (github.com/wyvernSemi, versions in
# 1.upstream/vip/README.md). Builds the DPI-C (Verilator, XSIM, JanusHDL) and VPI (Icarus)
# libraries, collects the headers and HDL, applies the local changes this
# test bench needs, and prints the directory, for the make file:
#
#   VIP_DIR=$(bash 4.build/build-vip.sh)
#
#   $VIP_DIR/lib        libcosimlnx.a (VProc), libpcielnx.a (pcieVHost)
#   $VIP_DIR/include    their C/C++ headers, ltssm.h
#   $VIP_DIR/hdl        f_VProc.sv, f_mem_model.sv, pcieVHost*.sv, clkmux.sv,
#                       Serialiser.sv; headers/ (.svh) for the include path
#
# Our changes to upstream are in 1.upstream/vip/ (4.build/vip-import.sh), but for
# 1.upstream/patches/pcievhost-speed.patch and 1.upstream/patches/vproc-coroutine.patch: VIP_PATCH and VPROC_PATCH below.
#
# VIP_BUILD (default ~/.cache/openPCIE_BFM/vip) is the output; it is
# rebuilt when a file in 1.upstream/vip/ or this script is newer, or VIP_PATCH has
# changed. Needs gcc, ar, and patch for VIP_PATCH.
#
# VIP_PATCH: a patch on the pcieVHost C sources, core, PIPE wrapper, serialiser
# and headers (-p1, a/src/..., a/verilog/..., upstream's .v names: mapped to
# our .sv and .svh), applied to a copy before the build: 1.upstream/patches/pcievhost-speed.patch for the Artix-7 RC
# model (the make file passes it). ltssm.c is not in the libraries:
# the make file compiles 3.sw/ltssm/ltssm.c with the user code.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../1.upstream/vip" && pwd)
OUT=${VIP_BUILD:-$HOME/.cache/openPCIE_BFM/vip}
VIP_PATCH=${VIP_PATCH:-}
VPROC_PATCH=${VPROC_PATCH:-}
STAMP=$({ [ -n "$VIP_PATCH" ] && cat "$VIP_PATCH"; [ -n "$VPROC_PATCH" ] && cat "$VPROC_PATCH"; echo; } | sha256sum)

if [ -f "$OUT/.built" ] && [ "$(cat "$OUT/.built")" = "$STAMP" ] &&
   [ -z "$(find "$SRC" "$0" -newer "$OUT/.built" -print -quit)" ]; then
    echo "$OUT"
    exit 0
fi

V=$SRC/vproc
P=$SRC/pcievhost
rm -rf "$OUT"
mkdir -p "$OUT"/{lib,include,hdl/headers,obj}
lf() { cat "$1"; }  # the copies are LF already

# PS: the pcieVHost C sources, patched with VIP_PATCH when given
PS=$P/src
PL=$P/verilog/lib
PV=$P/verilog/pcieVHost
PH=$P/verilog/headers
if [ -n "$VIP_PATCH" ]; then
    mkdir -p "$OUT/pcievhost/verilog"
    cp -r "$P/src" "$OUT/pcievhost/"
    cp -r "$P/verilog/lib" "$P/verilog/pcieVHost" "$P/verilog/headers" "$OUT/pcievhost/verilog/"
    sed -E '/^(---|\+\+\+) /{s#(/(headers|test)/\w+)\.v(\s|$)#\1.svh\3#;s#\.v(\s|$)#.sv\1#}' "$VIP_PATCH" |
        patch -s -p1 -d "$OUT/pcievhost" >&2
    PS=$OUT/pcievhost/src
    PL=$OUT/pcievhost/verilog/lib
    PV=$OUT/pcievhost/verilog/pcieVHost
    PH=$OUT/pcievhost/verilog/headers
fi
# VC: the VProc C sources, patched with VPROC_PATCH when given (the user code
# as a coroutine on the simulator's thread)
VC=$V/code
if [ -n "$VPROC_PATCH" ]; then
    mkdir -p "$OUT/vproc"
    cp -r "$VC" "$OUT/vproc/"
    patch -s -p1 -d "$OUT/vproc" < "$VPROC_PATCH" >&2
    VC=$OUT/vproc/code
fi
# ---- VProc: libcosimlnx.a (DPI-C), headers, HDL --------------------------------
for f in VSched VUser; do
    gcc -c -O2 -g -fPIC -m64 -I"$VC" -DVPROC_SV "$VC/$f.c" -o "$OUT/obj/$f.o"
done
ar cr "$OUT/lib/libcosimlnx.a" "$OUT"/obj/VSched.o "$OUT"/obj/VUser.o
for f in VProc.h VProcClass.h VProcIrqClass.h VSched_pli.h VUser.h; do
    lf "$VC/$f" > "$OUT/include/$f"
done
for f in f_VProc.sv extradefs.svh vprocdefs.vh vprocdpi.vh; do lf "$V/$f" > "$OUT/hdl/$f"; done

# ---- mem_model: HDL only (its C model is part of pcieVHost) ------------------
lf "$SRC/mem_model/f_mem_model.sv" > "$OUT/hdl/f_mem_model.sv"
lf "$SRC/mem_model/mem_model_dpi.vh" > "$OUT/hdl/mem_model_dpi.vh"

# ---- pcieVHost: libpcielnx.a, headers, HDL, LTSSM helper ----------------------
for f in codec mem pcie pcie_utils pcicrc32 displink; do
    gcc -c -O2 -g -fPIC -m64 -I"$VC" -DVPROC_SV "$PS/$f.c" -o "$OUT/obj/$f.o"
done
ar cr "$OUT/lib/libpcielnx.a" "$OUT"/obj/{codec,mem,pcie,pcie_utils,pcicrc32,displink}.o
for f in codec.h mem.h pci_express.h pcie.h pcieModelClass.h pcie_utils.h pcie_vhost_map.h ltssm.h; do
    lf "$PS/$f" > "$OUT/include/$f"
done

H=$OUT/hdl/headers
for f in allheaders.svh pciedispheader.svh pciexpress_header.svh timescale.svh; do
    lf "$PH/$f" > "$H/$f"
done
lf "$PH/pcie_vhost_map.svh" > "$H/pcie_vhost_map.svh"
lf "$P/verilog/test/test_defs.svh" > "$H/test_defs.svh"

for f in pcieVHost.sv pcieVHostPipex1.sv; do lf "$PV/$f" > "$OUT/hdl/$f"; done
for f in clkmux.sv Serialiser.sv; do lf "$PL/$f" > "$OUT/hdl/$f"; done

# ---- Icarus: the same C models, over VPI instead of DPI-C ------------------------
#   libcosimica.a  VProc, its VPI table supplied by pcieVHost's veriuser.c
#   libpcieica.a   pcieVHost with veriuser.c and mem_model.c
ICA_INC=$(dirname "$(command -v iverilog 2>/dev/null || echo /usr/bin/iverilog)")/../include/iverilog
if [ -f "$ICA_INC/vpi_user.h" ]; then
    ICA="-DICARUS -DVPROC_PLI_VPI -DEXTERN_VPI_TABLE -D_REENTRANT -I$ICA_INC"
    for f in VSched VUser; do
        gcc -c -O2 -g -fPIC -m64 -I"$VC" $ICA -Wno-int-to-pointer-cast "$VC/$f.c" -o "$OUT/obj/ica_$f.o"
    done
    ar cr "$OUT/lib/libcosimica.a" "$OUT"/obj/ica_VSched.o "$OUT"/obj/ica_VUser.o
    for f in codec mem mem_model pcie pcie_utils pcicrc32 displink veriuser; do
        gcc -c -O2 -g -fPIC -m64 -Wno-incompatible-pointer-types -Wno-format -I"$VC" -I"$ICA_INC" \
            -DICARUS "$PS/$f.c" -o "$OUT/obj/ica_$f.o"
    done
    ar cr "$OUT/lib/libpcieica.a" "$OUT"/obj/ica_{codec,mem,mem_model,pcie,pcie_utils,pcicrc32,displink,veriuser}.o
else
    echo "note: no Icarus VPI headers at $ICA_INC, Icarus libraries not built" >&2
fi

rm -rf "$OUT/obj"
cp "$SRC/README.md" "$OUT/VERSIONS.md"
echo "$STAMP" > "$OUT/.built"
echo "$OUT"

# -----------------------------------------------------------------------------
# Project:     openPCIE_BFM
# Description: PCIE simulation model on pcieVHost
# Version:     1.0
# Date:        April 2025
# -----------------------------------------------------------------------------
