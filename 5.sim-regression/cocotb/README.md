<!--
SPDX-FileCopyrightText: 2026 NK Verif Labs
SPDX-FileCopyrightText: 2026 CHILI.CHIPS.LLC

SPDX-License-Identifier: BSD-3-Clause
-->

# Cocotb + cocotbext-pcie Step 1 (TL + 7-Series TRN)

Drives `openCologne-PCIE` `tl_top` + `trn_compat` with `cocotbext-pcie` `RootComplex`
(`test_trn_rc.py`):

- Enumerates endpoint `01:00.0` (`Vendor/Device 0xCC00:0xCC00`), sizes and assigns `BAR0` (`4 KiB`).
- Verifies 2-DW (8-byte) and 1-DW (4-byte) `mem_write` / `mem_read` round-trips via a 7-series TRN BAR0 responder.

## Simulator Support

- **Verilator >= 5.036** with **cocotb 2.1.0** and **cocotbext-pcie** (`--timing --timescale 1ns/10ps`, zero `-Wno-*` waivers).
- **Icarus Verilog 12.0** is not supported for this target because it cannot compile SystemVerilog `interface.modport` ports on `tl_top.sv` and `trn_compat.sv`.

## Run

    make -C 5.sim-regression cocotb
