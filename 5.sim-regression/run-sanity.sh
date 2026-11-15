#!/bin/bash
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Sanity, after every change (README.md, Self-test): seven runs, about 3
# minutes. Each must end RC MODEL RESULT: PASS. Prints one line per run, logs
# in work/logs/sanity/; exits 1 if any run fails.
#
# Usage: bash run-sanity.sh [make variables, e.g. SEED=2]

set -u
cd "$(dirname "$0")"
LOG=work/logs/sanity
mkdir -p $LOG
fails=0

run() {  # name, make variables
    local n=$1 t0=$SECONDS r
    shift
    make run "$@" > $LOG/$n.log 2>&1
    r=$(grep -a -m1 'RC MODEL RESULT\|time limit' $LOG/$n.log)
    case "$r" in *"RESULT: PASS"*) ;; *) fails=$((fails + 1));; esac
    printf '%-16s %4d s  %-36s %s\n' "$n" $((SECONDS - t0)) "$*" "${r:-no result, see $LOG/$n.log}"
}

run verilator      SIM=verilator "$@"
run verilator-x4   SIM=verilator LANES=4 "$@"
run verilator-phy  SIM=verilator PHY=core "$@"
run verilator-a7rc SIM=verilator A7RC=1 "$@"
run icarus-x1      SIM=icarus WRAP=x1 "$@"
run xsim           SIM=xsim "$@"
run janushdl       SIM=janushdl "$@"

echo "sanity: $fails failed"
[ $fails = 0 ]
