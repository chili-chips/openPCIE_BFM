# SPDX-FileCopyrightText: 2026 NK Verif Labs
# SPDX-FileCopyrightText: 2026 CHILI.CHIPS.LLC
#
# SPDX-License-Identifier: BSD-3-Clause

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Lock, RisingEdge
from cocotb.utils import get_sim_steps
from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.core.port import SimPort
from cocotbext.pcie.core.tlp import Tlp, TlpType
from cocotbext.pcie.core.utils import PcieId


class TlDllSimPort(SimPort):
    def __init__(self, dut, rp):
        self.dut = dut
        self.rp = rp
        super().__init__(fc_init=[[32, 256, 32, 256, 32, 256]] * 8)
        self._rx_lock = Lock()
        self.rx_handler = self._to_dut

    async def _to_dut(self, pkt):
        async with self._rx_lock:
            raw = pkt.pack()
            n_beats = (len(raw) + 7) // 8
            for i in range(n_beats):
                chunk = raw[8 * i : 8 * i + 8].ljust(8, b"\x00")
                self.dut.rx_data_i.value = int.from_bytes(chunk, "little")
                self.dut.rx_valid_i.value = 1
                self.dut.rx_first_i.value = 1 if i == 0 else 0
                self.dut.rx_last_i.value = 1 if i == n_beats - 1 else 0
                self.dut.rx_half_i.value = 0
                await RisingEdge(self.dut.clk)
            self.dut.rx_valid_i.value = 0
            self.dut.rx_first_i.value = 0
            self.dut.rx_last_i.value = 0
            self.dut.rx_data_i.value = 0

    async def run_dut_tx_monitor(self):
        buf = bytearray()
        while True:
            await RisingEdge(self.dut.clk)
            if int(self.dut.tx_valid_o.value):
                if int(self.dut.tx_first_o.value):
                    buf = bytearray()
                word = int(self.dut.tx_data_o.value).to_bytes(8, "little")
                if int(self.dut.tx_last_o.value) and int(self.dut.tx_half_o.value):
                    buf.extend(word[:4])
                else:
                    buf.extend(word)
                if int(self.dut.tx_last_o.value):
                    tlp = Tlp.unpack(bytes(buf))
                    self.dut.tx_ready_i.value = 0
                    await RisingEdge(self.dut.clk)
                    self.dut.tx_ready_i.value = 1
                    await self.rp.downstream_recv(tlp)


async def trn_bar0_responder(dut, mem, dev_id):
    buf = bytearray()
    while True:
        await RisingEdge(dut.clk)
        if int(dut.trn_rsrc_rdy_o.value) and int(dut.trn_rdst_rdy_i.value):
            if int(dut.trn_rsof_o.value):
                buf = bytearray()
            val = int(dut.trn_rd_o.value)
            dw_hi = (val >> 32) & 0xFFFFFFFF
            dw_lo = val & 0xFFFFFFFF
            buf.extend(dw_hi.to_bytes(4, "little"))
            eof = int(dut.trn_reof_o.value)
            rem = int(dut.trn_rrem_o.value)
            if not eof or rem:
                buf.extend(dw_lo.to_bytes(4, "little"))
            if eof:
                tlp = Tlp.unpack(bytes(buf))
                offset = tlp.address & 0xFFF
                if tlp.fmt_type == TlpType.MEM_WRITE:
                    data = bytes(tlp.data)
                    mem[offset : offset + len(data)] = data
                elif tlp.fmt_type == TlpType.MEM_READ:
                    nbytes = tlp.length * 4
                    payload = bytes(mem[offset : offset + nbytes])
                    cpl = Tlp.create_completion_data_for_tlp(tlp, dev_id)
                    cpl.set_data(payload)
                    cpl_raw = cpl.pack()
                    dws = [
                        int.from_bytes(cpl_raw[4 * k : 4 * k + 4], "little")
                        for k in range(len(cpl_raw) // 4)
                    ]
                    n_beats = (len(dws) + 1) // 2
                    for i in range(n_beats):
                        hi = dws[2 * i]
                        lo = dws[2 * i + 1] if (2 * i + 1) < len(dws) else 0
                        dut.trn_td_i.value = (hi << 32) | lo
                        dut.trn_tsof_i.value = 1 if i == 0 else 0
                        dut.trn_teof_i.value = 1 if i == n_beats - 1 else 0
                        dut.trn_tsrc_rdy_i.value = 1
                        await RisingEdge(dut.clk)
                        while not int(dut.trn_tdst_rdy_o.value):
                            await RisingEdge(dut.clk)
                    dut.trn_tsrc_rdy_i.value = 0
                    dut.trn_tsof_i.value = 0
                    dut.trn_teof_i.value = 0


@cocotb.test()
async def test_enum_and_bar0_rw(dut):
    cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())
    dut.rst_n.value = 0
    dut.dl_state_i.value = 0
    dut.rx_valid_i.value = 0
    dut.rx_first_i.value = 0
    dut.rx_last_i.value = 0
    dut.rx_half_i.value = 0
    dut.rx_data_i.value = 0
    dut.tx_ready_i.value = 1
    dut.fc_valid_i.value = 0
    dut.fc_pkt_type_i.value = 0
    dut.fc_class_i.value = 0
    dut.fc_hdr_i.value = 0
    dut.fc_data_i.value = 0
    dut.trn_td_i.value = 0
    dut.trn_tsof_i.value = 0
    dut.trn_teof_i.value = 0
    dut.trn_tsrc_rdy_i.value = 0
    dut.trn_rdst_rdy_i.value = 1

    for _ in range(4):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1
    for st, pt in [(1, 1), (2, 3)]:  # DL_INITFC1/INITFC1, DL_INITFC2/INITFC2
        dut.dl_state_i.value = st
        for fc_cls in range(3):
            dut.fc_valid_i.value = 1
            dut.fc_pkt_type_i.value = pt
            dut.fc_class_i.value = fc_cls
            dut.fc_hdr_i.value = 32
            dut.fc_data_i.value = 256
            await RisingEdge(dut.clk)
    dut.dl_state_i.value = 3  # DL_ACTIVE
    dut.fc_valid_i.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.trn_lnk_up_o.value) == 1

    bar_mem = bytearray(4096)
    cocotb.start_soon(trn_bar0_responder(dut, bar_mem, PcieId(1, 0, 0)))

    rc = RootComplex()
    rp = rc.make_port()
    ep_port = TlDllSimPort(dut, rp)
    rp.downstream_port.connect(ep_port)
    rp.downstream_port.max_latency_timer_steps = get_sim_steps(1, "us")
    ep_port.max_latency_timer_steps = get_sim_steps(1, "us")
    cocotb.start_soon(ep_port.run_dut_tx_monitor())

    await rc.enumerate()
    ep = rc.find_device((1, 0, 0))
    assert ep is not None, "Endpoint not discovered during enumeration"
    bar0 = ep.bar[0] & ~0xF
    assert bar0 != 0, "BAR0 not assigned"

    await rc.mem_write(bar0 + 0x10, b"\xDE\xAD\xBE\xEF\xCA\xFE\xBA\xBE")
    rd = await rc.mem_read(bar0 + 0x10, 8)
    assert rd == b"\xDE\xAD\xBE\xEF\xCA\xFE\xBA\xBE", f"BAR0 mismatch: {rd.hex()}"
    await rc.mem_write(bar0 + 0x24, b"\x12\x34\x56\x78")
    rd4 = await rc.mem_read(bar0 + 0x24, 4)
    assert rd4 == b"\x12\x34\x56\x78", f"BAR0 1-DW mismatch: {rd4.hex()}"
