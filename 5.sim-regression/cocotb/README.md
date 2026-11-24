# Cocotb PIPE Bring-Up Smoke Test (`pipe_phy_core`)

Verifies `2.rtl/pipe_phy_core.sv` across PIPE reset, `P1` receiver detection (`rx_status == 3'b011`), `P1 -> P0` transition, and `L0` COM (`K28.5 = 0xBC`) symbol lock using Cocotb + Verilator.

    make SIM=verilator
