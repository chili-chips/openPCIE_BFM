#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Writes a WaveCrux session for an FST of the self-test (make WAVES=1 run):
# the rows and decoders of LAYOUTS below, bound to that file. A session binds
# by signal number in the file ("ref": the order in which the FST's signal
# handles first appear), and that number differs from one simulator to the
# next, so each FST gets its own session, made from the signal names.
#
#   wavecrux-session.py LAYOUT FST SESSION
#
# LAYOUT is x1 or x4. The session names the FST by its file name: keep the
# two side by side. The view shows the whole run. Needs fst2vcd (GTKWave or
# the OSS CAD Suite) on PATH. Standard library only.
#
# Colours: RC -> EP (dn) blue, EP -> RC (up) orange, reset and rate yellow.

import json
import os
import struct
import subprocess
import sys

DN, UP, CTL = 4283417591, 4294948685, 4294962776   # ARGB: #4FC3F7, #FFB74D, #FFF176
RC = 'tb.u_rc.'                                     # the RC wrapper's taps (2.rtl/PIPExN__pcieVHost.sv)
PIPE_PAR = {'scrambling': 'auto', 'sample_point': 'before_edge'}
X4_PAR = {'max_skew': 8, 'lane_order': 'auto'}      # the EP reverses its lanes (LANE_REV_EP)


def pipe_rows(x4):
    if not x4:
        return [(RC + 'pipe_dn_data', DN), (RC + 'pipe_dn_datak', DN),
                (RC + 'pipe_up_data', UP), (RC + 'pipe_up_datak', UP)]
    v = 'tb.pipe_view.'
    return ([(v + 'pipe_dn_data' + s, DN) for s in ('', '1', '2', '3')]
            + [(v + 'pipe_up_data' + s, UP) for s in ('', '1', '2', '3')])


def pipe_bind(x4, d):
    p = (RC if not x4 else 'tb.pipe_view.') + 'pipe_' + d + '_'
    b = {'pclk': p + 'pclk', 'data': p + 'data', 'datak': p + 'datak'}
    if x4:
        for l in ('1', '2', '3'):
            b['data' + l], b['datak' + l] = p + 'data' + l, p + 'datak' + l
    return b


def tlp_bind(pfx):
    return {k: RC + pfx + k for k in ('clk', 'tlp_data', 'tlp_sop', 'tlp_eop', 'tlp_valid',
                                      'peer_data', 'peer_sop', 'peer_eop', 'peer_valid')}


def layout(x4):
    rows = [(RC + 'nreset', CTL), (RC + 'gen2', CTL)] + pipe_rows(x4) + [
        (RC + 'dllp_dn_valid', DN), (RC + 'dllp_dn_data', DN),
        (RC + 'dllp_up_valid', UP), (RC + 'dllp_up_data', UP),
        (RC + 'tx_tlp_valid', DN), (RC + 'tx_tlp_data', DN),
        (RC + 'rx_tlp_valid', UP), (RC + 'rx_tlp_data', UP)]
    par = dict(PIPE_PAR, **(X4_PAR if x4 else {}))
    w = 'ferrite.pcie_%s_w16'
    dec = []
    for n, d in ((1, 'dn'), (2, 'up')):
        dec.append((w % 'dll', n, pipe_bind(x4, d), dict(par)))
    for n, d in ((1, 'dn'), (2, 'up')):
        dec.append((w % 'pipe', n, pipe_bind(x4, d), dict(par, coalesce=True, show_idle=False)))
    dec.append(('openpcie.pcie_tlp_down', 1, tlp_bind('tx_'), {'span': 'until_next'}))
    dec.append(('openpcie.pcie_tlp_up', 1, tlp_bind('rx_'), {'span': 'until_next'}))
    return rows, dec


LAYOUTS = {'x1': layout(False), 'x4': layout(True)}
OPTIONAL = {RC + 'gen2'}                            # not on the x1 Gen1 wrappers (make WRAP=x1)


def fst_refs(fst):
    """path -> ref: the number of the path's handle (its VCD id code), in the
    order the handles first appear. Reads the header only."""
    p = subprocess.Popen(['fst2vcd', fst], stdout=subprocess.PIPE, text=True, errors='replace')
    refs, handles, scope = {}, {}, []
    for line in p.stdout:
        w = line.split()
        if line.startswith('$enddefinitions'):
            break
        if line.startswith('$scope'):
            scope.append(w[2])
        elif line.startswith('$upscope'):
            scope.pop()
        elif line.startswith('$var'):
            h = handles.setdefault(w[3], str(len(handles)))
            refs.setdefault('.'.join(scope + [w[4]]), h)
    p.kill()
    p.wait()
    return refs


def fst_end_ticks(fst):
    """the FST's end time in WaveCrux ticks (100 fs), from its header block"""
    with open(fst, 'rb') as f:
        h = f.read(1 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 1)
    if len(h) < 74 or h[0] != 0:
        return 0
    end = struct.unpack('>Q', h[17:25])[0]
    exp = struct.unpack('b', h[73:74])[0]   # time unit, 10**exp s
    return end * 10 ** (exp + 13) if exp + 13 >= 0 else end // 10 ** -(exp + 13)


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in LAYOUTS:
        sys.exit('usage: wavecrux-session.py x1|x4 FST SESSION')
    name, fst, out = sys.argv[1:]
    rows, decs = LAYOUTS[name]
    refs = fst_refs(fst)
    rows = [(p, c) for p, c in rows if p in refs or p not in OPTIONAL]
    missing = sorted(({p for p, _ in rows} | {p for d in decs for p in d[2].values()}) - set(refs))
    if missing:
        sys.exit('wavecrux-session.py: not in %s: %s' % (fst, ', '.join(missing)))

    ticks = fst_end_ticks(fst)
    d = {
        'version': 4,
        'sourceFilePath': os.path.basename(fst),
        'signals': [{'kind': 'signal', 'id': 'bfm-%d' % i, 'ref': refs[p], 'path': p,
                     'name': p.rsplit('.', 1)[1], 'color': c, 'format': 'hexadecimal', 'height': 30.0}
                    for i, (p, c) in enumerate(rows)],
        'cursor': {'primary': None, 'secondary': None},
        'markers': {},
        'view': {'ticksPerPixel': float(max(ticks // 1300, 1)), 'panOffsetTicks': 0.0, 'scrollOffset': 0.0},
        'panels': {'signalTree': False, 'valueColumn': False, 'transactionView': False, 'stageView': False,
                   'statisticsStrip': False, 'cocotbLogPanel': False, 'rtlSource': False,
                   'sizes': {'left': 301.6, 'right': 150.0}},
        'signalTreeState': {'expanded': [], 'selected': [], 'scroll': 0.0},
        'translateFilters': {},
        'stage': {'panels': []},
        'activeTheme': 'wavecrux-dark',
        'decoders': [{'decoderId': i, 'instanceNumber': n,
                      'config': {'bindings': {k: refs[p] for k, p in b.items()}, 'parameters': par}}
                     for i, n, b, par in decs],
    }
    with open(out, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    print('%s: %d rows, %d decoders, for %s' % (out, len(rows), len(decs), os.path.basename(fst)))


if __name__ == '__main__':
    main()

# -----------------------------------------------------------------------------
# Project:     openPCIE_BFM
# Description: PCIE simulation model, built on pcieVHost
# Version:     1.0
# Date:        Nov 14, 2026
# -----------------------------------------------------------------------------
