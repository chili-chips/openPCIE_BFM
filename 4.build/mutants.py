#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
"""make mutants: the RC model's checker against broken endpoints.

Each mutant breaks the pcieVHost endpoint model (its user code, or the LTSSM
code it shares with the RC model) in one way, in its own copy of the calling
repo under OUT/<name>/, runs the make command there, and must fail the rule
it breaks. Shared by openPCIE_BFM (5.sim-regression), openPCIE and
openCologne-PCIE (5.sim). Run from the simulation folder.

Usage: mutants.py [--jobs N] [--out DIR] [--ep FILE] [--need NAME=ARGS]...
                  -- make arguments...

  --jobs   mutants side by side (default 3)
  --out    where the copies go (default obj/mutants)
  --ep     the endpoint model's user code, from the simulation folder
           (default usercode/VUserMain1.cpp)
  --need   a capability the repo has, and the make arguments it takes:
           gen2 (the tester's Gen2 speed changes run), gen1-rc (a Gen1 RC
           and a Gen2 endpoint that changes the speed itself). A mutant
           whose need is not given is not applicable here (n/a)

Prints one line per mutant; exits 1 if a mutant passes, misses its rule, or
gives no result.
"""

import argparse
import os
import re
import shlex
import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BFM = Path(__file__).resolve().parents[1]
EXCLUDES = ['.git', 'obj', 'work', 'xsim.dir', 'build_artifacts', '*.fst', '*.vcd']
TIMEOUT_S = 3600

# Edits: (role, anchor, insert, where). role: 'ep' (the --ep file) or 'ltssm'
# (the BFM's 3.sw/ltssm/ltssm.c); anchor: a regex that must match one line;
# where: 'after' that line, 'before' it, or 'replace' the match.
# The 'ep' anchors are in every endpoint model: link training starts
# (InitLink or InitLinkGen), flow control is set up (initFc), the idle loop.
EP_TRAIN = r'^    InitLink(Gen)?\('
EP_FC = r'^    pcie->initFc\(\);$'
EP_LOOP = r'^        LinkIdle\(100, node\);$'

# name, the rule it must fail, needs, edits
MUTANTS = [
    # Physical Layer
    ('pl-skp', 'PL.SKP', None, [
        ('ep', EP_TRAIN, '    pcie->configurePcie(CONFIG_DISABLE_SKIPS);   // MUTANT: no SKP', 'before')]),
    ('pl-ts-fields', 'PL.TS-FIELDS', None, [
        ('ep', EP_TRAIN, '    ConfigurePcieLtssm(CONFIG_LTSSM_TS_CTL, 0x10, node);   // MUTANT: reserved bit',
         'before')]),
    ('pl-eios-count', 'PL.EIOS', 'gen2', [
        ('ltssm', r'for \(int i = 0; i < ltssm_cur_gen\[node\]; i\+\+\)',
         'for (int i = 0; i < 1; i++)   /* MUTANT: one EIOS at any rate */', 'replace')]),
    ('pl-eios-idle', 'PL.EIOS', 'gen2', [
        ('ltssm', r'SendIdle\(idle_us \* ticks_us, node\);',
         'SendIdle(100, node);   /* MUTANT: idle too short */', 'replace')]),
    ('pl-eios-lock', 'PL.EIOS', 'gen2', [
        ('ltssm', re.escape('timeout  = RECOVERY_RCVRLOCK_TO_US * SYMCLK_TICKS_PER_US(ltssm_cur_gen[node]) / TS_TICKS;'),
         'timeout  = (ltssm_cur_gen[node] == 2) ? 4 : RECOVERY_RCVRLOCK_TO_US * SYMCLK_TICKS_PER_US(1) / TS_TICKS;'
         '   /* MUTANT: RcvrLock at 5.0 GT/s gives up long before 24 ms */', 'replace')]),
    ('pl-eios-gen1', 'PL.EIOS', 'gen1-rc', [
        ('ltssm', re.escape('to_speed = directed && (ltssm_cur_gen[node] > 1 || '
                            '(ltssm_rate[node] & partner & TS_DATA_RATE_5G));'),
         'to_speed = directed;   /* MUTANT: Recovery.Speed at 2.5 GT/s without 5.0 GT/s (issue 47) */',
         'replace')]),
    # Data Link Layer: the hooks of pcievhost-speed.patch, from the endpoint
    ('dl-lcrc', 'DL.LCRC', None, [
        ('ep', EP_FC, '    InjectFault(FAULT_TX_BAD_LCRC, node);   // MUTANT: a TLP with a bad LCRC', 'after')]),
    ('dl-dllp-crc', 'DL.DLLP-CRC', None, [
        ('ep', EP_FC, '    InjectFault(FAULT_TX_BAD_DLLP, node);   // MUTANT: a DLLP with a bad CRC', 'after')]),
    ('dl-nak', 'DL.NAK', None, [
        ('ep', EP_FC, '    InjectFault(FAULT_RX_NAK_NEXT, node);   // MUTANT: Naks a good TLP', 'after')]),
    ('dl-ack-lat', 'DL.ACK-LAT', None, [
        ('ep', EP_FC, '    pcie->configurePcie(CONFIG_ENABLE_ACK, 5000);   // MUTANT: Acks 5000 ticks late',
         'after')]),
    ('dl-dup', 'DL.REPLAY', None, [
        ('ep', EP_FC, '    InjectFault(FAULT_TX_DUP, node);   // MUTANT: a TLP sent again, no Nak, no timeout',
         'after'),
        ('ep', EP_LOOP, '        SendDuplicate(node);   // MUTANT', 'after')]),
    # Flow control
    ('fc-update', 'FC.UPDATE-PERIOD', None, [
        ('ep', EP_FC, '    HoldFc(50000, node);   // MUTANT: no UpdateFC for 50000 ticks (100 us at Gen2)', 'after')]),
]


def edit(path, anchor, insert, where):
    s = path.read_text()
    hits = list(re.finditer(anchor, s, re.M))
    if len(hits) != 1:
        return f'"{anchor}" found {len(hits)} times in {path.name}'
    m = hits[0]
    if where == 'replace':
        s = s[:m.start()] + insert + s[m.end():]
    else:
        bol = s.rfind('\n', 0, m.start()) + 1
        eol = s.find('\n', m.end())
        eol = len(s) if eol < 0 else eol + 1
        s = s[:bol] + insert + '\n' + s[bol:] if where == 'before' else s[:eol] + insert + '\n' + s[eol:]
    path.write_text(s)
    return None


def run(mutant, cfg):
    name, rule, need, edits = mutant
    if need and need not in cfg.need:
        return f'mutant {name}: n/a here (needs {need})'
    d = cfg.out / name
    d.mkdir(parents=True, exist_ok=True)
    subprocess.run(['rsync', '-a', '--delete', '--delete-excluded'] + [f'--exclude={e}' for e in EXCLUDES] +
                   [f'{cfg.root}/', f'{d}/repo/'], check=True)
    sim = d / 'repo' / cfg.sim
    files = {'ep': sim / cfg.ep, 'ltssm': d / 'repo' / cfg.bfm / '3.sw' / 'ltssm' / 'ltssm.c'}
    for role, anchor, insert, where in edits:
        err = edit(files[role], anchor, insert, where)
        if err:
            return f'mutant {name}: cannot apply, {err}'
    log = d / 'mutant.log'
    # a make of its own: none of the calling make's flags or jobserver
    env = {k: v for k, v in os.environ.items() if k not in ('MAKEFLAGS', 'MFLAGS', 'MAKELEVEL')}
    args = cfg.make + (shlex.split(cfg.need[need]) if need else [])
    with open(log, 'w') as fh:
        p = subprocess.Popen(['make'] + args, cwd=sim, stdout=fh, stderr=subprocess.STDOUT, env=env,
                             start_new_session=True)
        try:
            p.wait(timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)   # the simulator too
            p.wait()
    s = log.read_text(errors='replace')
    fails = sorted(set(re.findall(r'^\*\*\*\* CHECK (\S+) ', s, re.M)))
    if 'RC MODEL RESULT: FAIL' in s and rule in fails:
        return f'mutant {name}: fails {rule}, as it must ({", ".join(fails)}) ({log})'
    if 'RC MODEL RESULT: PASS' in s:
        return f'mutant {name}: MISSED, the run passes ({log})'
    if 'RC MODEL RESULT' in s:
        return f'mutant {name}: MISSED, fails {", ".join(fails) or "the tester"}, not {rule} ({log})'
    return f'mutant {name}: no result ({log})'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--jobs', type=int, default=3)
    ap.add_argument('--out', default='obj/mutants')
    ap.add_argument('--ep', default='usercode/VUserMain1.cpp')
    ap.add_argument('--need', action='append', default=[], metavar='NAME=ARGS')
    ap.add_argument('--only', default='', help='comma-separated mutant names (default all)')
    ap.add_argument('make', nargs='*')
    cfg = ap.parse_args()
    cfg.need = dict(n.split('=', 1) if '=' in n else (n, '') for n in cfg.need)
    here = Path.cwd().resolve()
    cfg.root = Path(subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True,
                                   check=True).stdout.strip()).resolve()
    cfg.sim = here.relative_to(cfg.root)
    cfg.bfm = BFM.relative_to(cfg.root)
    cfg.out = (here / cfg.out).resolve()
    cfg.make = cfg.make or ['run']
    todo = [m for m in MUTANTS if not cfg.only or m[0] in cfg.only.split(',')]
    with ThreadPoolExecutor(max_workers=cfg.jobs) as ex:
        lines = list(ex.map(lambda m: run(m, cfg), todo))
    bad = na = 0
    for line in lines:
        print(line)
        na += 'n/a here' in line
        bad += 'as it must' not in line and 'n/a here' not in line
    print(f'{bad} of {len(todo) - na} mutants missed ({na} n/a here)')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
