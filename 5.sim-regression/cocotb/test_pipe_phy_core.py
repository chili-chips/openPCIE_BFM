import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def wait_phy_status(dut, limit=40):
    for _ in range(limit):
        await RisingEdge(dut.pclk); await Timer(1, units="ns")
        if int(dut.phy_status.value) == 1:
            return
    raise AssertionError("Timed out waiting for phy_status pulse")

@cocotb.test()
async def test_pipe_bringup_and_com_lock(dut):
    cocotb.start_soon(Clock(dut.pclk, 8, units="ns").start())
    dut.rst_n.value = 0; dut.mac_reset.value = 1; dut.powerdown.value = 2; dut.rate.value = 0
    dut.tx_detect_rx.value = 0; dut.tx_elec_idle.value = 1; dut.tx_data.value = 0; dut.tx_datak.value = 0
    dut.rcvr_present.value = 1; dut.host_txdata.value = 0xFFFF; dut.host_txdatak.value = 0b11
    for _ in range(4): await RisingEdge(dut.pclk)
    dut.rst_n.value = 1
    while int(dut.phy_rdy.value) == 0: await RisingEdge(dut.pclk)
    dut.mac_reset.value = 0
    for _ in range(12): await RisingEdge(dut.pclk)
    assert int(dut.phy_status.value) == 0
    dut.tx_detect_rx.value = 1
    await wait_phy_status(dut)
    assert int(dut.rx_status.value) == 0b011
    dut.tx_detect_rx.value = 0
    dut.powerdown.value = 0
    await wait_phy_status(dut)
    dut.tx_elec_idle.value = 0; dut.host_txdatak.value = 0b01; dut.host_txdata.value = 0x00BC
    for _ in range(4): await RisingEdge(dut.pclk)
    await Timer(1, units="ns")
    assert int(dut.rx_valid.value) == 1 and int(dut.rx_elec_idle.value) == 0
    assert (int(dut.rx_data.value) & 0xFF) == 0xBC and (int(dut.rx_datak.value) & 1) == 1
