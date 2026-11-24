#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Regression, before a push (README.md, Self-test): every simulator in every
# configuration (SIMS x CONFIGS), then 10 seeds on Verilator. Each run must end
# RC MODEL RESULT: PASS, and at WRAP=x1 every simulator must print the same
# ===> lines. A run in KNOWN fails on an open simulator issue: it fails as
# known (its log shows the signature) without failing the list; a PASS is fine
# too ("known ... not hit"). Prints one line per run, logs in
# work/logs/regression/; exits 1 if a run fails otherwise.
# To add a simulator: SIM=<name> in the Makefile, the name in SIMS.
#
# Usage: bash run-regression.sh [make variables, e.g. SEED=2]

set -u
cd "$(dirname "$0")"
LOG=work/logs/regression
mkdir -p $LOG
fails=0

SIMS="verilator icarus xsim janushdl"
declare -A CONFIGS=(          # name: make variables
    [default]=""
    [x1]="WRAP=x1"
    [x1-a7rc]="WRAP=x1 A7RC=1"
    [x4]="LANES=4"
    [phy]="PHY=core"
    [x4-phy]="LANES=4 PHY=core"
    [a7rc]="A7RC=1"
    [gen1]="GEN=1"
)
ORDER="default x1 x1-a7rc x4 phy x4-phy a7rc gen1"

# sim:config: "issue|signature in the log (grep -E)"
ICARUS_X4="iverilog#521, loop index on the outer dimension of a packed array|pcieVHostPipexN.sv:135"
ICARUS_SVA="iverilog#120, no SVA (assert property)|pipe_mac_adapter.sv:193"
declare -A KNOWN=(
    [icarus:x4]=$ICARUS_X4
    [icarus:phy]=$ICARUS_SVA
    [icarus:x4-phy]="iverilog#521 and #120|pcieVHostPipexN.sv:135|pipe_mac_adapter.sv:193"
)

report() {  # name, seconds, pass (0/1), what, result, [known: "issue|signature"]
    local k=${6:-} st
    if [ $3 = 1 ]; then st=PASS; [ -z "$k" ] || st="PASS (known ${k%%|*} not hit)"
    elif [ -n "$k" ] && grep -a -q -E "${k#*|}" $LOG/$1.log; then st="known: ${k%%|*}"
    else st=FAIL; fails=$((fails + 1)); fi
    printf '%-20s %4d s  %-38s %s  (%s)\n' "$1" "$2" "$4" "$st" "$5"
}

run() {  # sim, config
    local n=$1-$2 t0=$SECONDS r ok=0
    make --no-print-directory run SIM=$1 ${CONFIGS[$2]} "${EXTRA[@]}" > $LOG/$n.log 2>&1
    r=$(grep -a -m1 'RC MODEL RESULT\|time limit' $LOG/$n.log)
    case "$r" in *"RESULT: PASS"*) ok=1;; esac
    report $n $((SECONDS - t0)) $ok "SIM=$1 ${CONFIGS[$2]}" "${r:-no result}" "${KNOWN[$1:$2]:-}"
}

EXTRA=("$@")
for s in $SIMS; do for c in $ORDER; do run $s $c; done; done

# WRAP=x1 runs on every simulator: the same ===> lines (faults, rule counts,
# result). JanusHDL's end line may land inside a ===> line: taken out
marks() { sed -z 's/simulation of tb ended at [^\n]*\n//' $1 | grep -a '===>'; }
d=""
for s in $SIMS; do
    diff -q <(marks $LOG/verilator-x1.log) <(marks $LOG/$s-x1.log) > /dev/null || d="$d $s"
done
if [ -z "$d" ]; then report sim-match 0 1 "WRAP=x1, every simulator" "the same ===> lines"
else report sim-match 0 0 "WRAP=x1, every simulator" "differ from Verilator:$d"; fi

t0=$SECONDS
make --no-print-directory regress SIM=verilator SEEDS=10 REGRESS_JOBS=4 "$@" > $LOG/regress.log 2>&1
r=$(grep -a 'seeds failed$' $LOG/regress.log)
case "$r" in "0 of "*) ok=1;; *) ok=0;; esac
report regress $((SECONDS - t0)) $ok "regress SIM=verilator SEEDS=10" "$r; $(grep -a 'checked in no seed' $LOG/regress.log)"

# Sustained load (make MIX=N): 1000 mix requests on the serial line at +300 ppm
t0=$SECONDS
make --no-print-directory run SIM=verilator IFACE=serial PPM=300 MIX=1000 "$@" > $LOG/load.log 2>&1
r=$(grep -a -m1 'RC MODEL RESULT\|time limit' $LOG/load.log)
case "$r" in *"RESULT: PASS"*) ok=1;; *) ok=0;; esac
report load $((SECONDS - t0)) $ok "IFACE=serial PPM=300 MIX=1000" "${r:-no result}"

# The checker against broken endpoints (../4.build/mutants.py)
t0=$SECONDS
make --no-print-directory mutants SIM=verilator MUTANT_JOBS=6 > $LOG/mutants.log 2>&1 && ok=1 || ok=0
report mutants $((SECONDS - t0)) $ok "mutants" "$(grep -a 'mutants missed' $LOG/mutants.log)"

echo "regression: $fails failed"
[ $fails = 0 ]
