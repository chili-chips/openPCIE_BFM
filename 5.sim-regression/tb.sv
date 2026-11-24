// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// openPCIE_BFM * PCIE simulation model, built on pcieVHost
//--------------------------------------------------------------------------
//                   Copyright (C) 2026 Chili.CHIPS
//
//              https://opensource.org/license/bsd-3-clause
//--------------------------------------------------------------------------
// Description:
//   Self-test: two pcieVHost nodes back to back on a PIPE link, x1 or x4,
//   Gen1 or Gen2. The bench of openPCIE's make RC=model (tb_rc.sv), without
//   its project package: the width comes from `SIM_LANES.
//
//        u_rc  PIPExN__pcieVHost, EndPoint = 0   <-- the Artix-7 RC model,
//          |   PIPE                                  node 2 (3.sw/a7rc/)
//        u_ep  PIPExN__pcieVHost, EndPoint = 1   <-- the endpoint model,
//                                                    node 1 (usercode/)
//
//   SIM_PIPE_PHY (make PHY=core): a PIPE PHY between them, the RC model as
//   its MAC
//
//        u_rc  -> u_mac  pipe_mac_adapter (the MAC side of the PIPE)
//                 |      PIPE, with its handshakes
//                 u_phy  pipe_phy_core    (the PHY side) -> u_ep
//
//   The run ends when the RC model has checked the endpoint (RC MODEL
//   RESULT), or at the time limit `RUN_US.
//==========================================================================

`ifndef SIM_LANES
`define SIM_LANES 1
`endif
`ifndef RUN_US
`define RUN_US 2000
`endif

module tb;

  import openPCIE_BFM_pkg::*;

  // PCLK at 16 bits per lane: 125 MHz at Gen1, 250 MHz at Gen2. The RC model
  // sets the rate (Gen2ClkSel); both models make their symbol clock from PCLK
  localparam int PCLK_HALF_GEN1_PS = 4000;
  localparam int PCLK_HALF_GEN2_PS = 2000;

  bit   pclk;
  bit   nreset;     // PERST#: the RC model
  bit   ep_nreset;  // the endpoint, a little later
  bit   rate_sel;
  logic rc_gen2;

  initial begin
    pclk      = 1'b0;
    nreset    = 1'b0;
    ep_nreset = 1'b0;
    rate_sel  = 1'b0;
  end

  always @(rc_gen2) rate_sel = (rc_gen2 === 1'b1);

  always #((rate_sel ? PCLK_HALF_GEN2_PS : PCLK_HALF_GEN1_PS) * 1ns / 1000.0) pclk = ~pclk;

  initial begin
    #(1us) nreset <= 1'b1;
    #(487ns) ep_nreset <= 1'b1;
    #(`RUN_US * 1us - 1us - 487ns);
    $fatal(1, "time limit of %0d us: no RC MODEL RESULT", `RUN_US);
  end

  localparam int L = `SIM_LANES;  // make LANES: 1 or 4

  bit   [16*L-1:0] rc_rx_data, ep_rx_data;
  bit   [ 2*L-1:0] rc_rx_datak, ep_rx_datak;
  logic [16*L-1:0] rc_tx_data, ep_tx_data;
  logic [ 2*L-1:0] rc_tx_datak, ep_tx_datak;

`ifdef SIM_PIPE_PHY
  logic [16*L-1:0] p_tx_data, p_rx_data, ep_tx_q;
  logic [ 2*L-1:0] p_tx_datak, p_rx_datak, ep_txk_q;
  logic [   L-1:0] p_tx_elec_idle, p_rx_valid, p_rx_elec_idle;
  logic [     1:0] p_powerdown;
  logic [     2:0] p_rx_status;
  logic            p_mac_reset, p_rate, p_tx_detect_rx, p_phy_status;

  pipe_mac_adapter #(
      .LANES (L),
      .BYTES (2)
  ) u_mac (
      .pclk         (pclk),
      .rst_n        (nreset),
      .link_up      (),
      .vh_gen2      (rc_gen2),
      .vh_txdata    (rc_tx_data),
      .vh_txdatak   (rc_tx_datak),
      .vh_rxdata    (rc_rx_data),
      .vh_rxdatak   (rc_rx_datak),
      .mac_reset    (p_mac_reset),
      .powerdown    (p_powerdown),
      .rate         (p_rate),
      .tx_detect_rx (p_tx_detect_rx),
      .tx_elec_idle (p_tx_elec_idle),
      .tx_data      (p_tx_data),
      .tx_datak     (p_tx_datak),
      .phy_status   (p_phy_status),
      .rx_status    (p_rx_status),
      .rx_valid     (p_rx_valid),
      .rx_elec_idle (p_rx_elec_idle),
      .rx_data      (p_rx_data),
      .rx_datak     (p_rx_datak)
  );

  pipe_phy_core #(
      .LANES   (L),
      .BYTES   (2),
      .TX_FLOP (1)
  ) u_phy (
      .pclk         (pclk),
      .rst_n        (nreset),
      .phy_rdy      (),
      .mac_reset    (p_mac_reset),
      .powerdown    (p_powerdown),
      .rate         (p_rate),
      .tx_detect_rx (p_tx_detect_rx),
      .tx_elec_idle (p_tx_elec_idle),
      .tx_data      (p_tx_data),
      .tx_datak     (p_tx_datak),
      .phy_status   (p_phy_status),
      .rx_status    (p_rx_status),
      .rx_valid     (p_rx_valid),
      .rx_elec_idle (p_rx_elec_idle),
      .rx_data      (p_rx_data),
      .rx_datak     (p_rx_datak),
      .rcvr_present (ep_nreset),
      .host_rxdata  (ep_rx_data),
      .host_rxdatak (ep_rx_datak),
      .host_txdata  (ep_tx_q),
      .host_txdatak (ep_txk_q)
  );

  // the endpoint's TX through one register stage, as on the link without PHY
  always_ff @(posedge pclk or negedge nreset) begin
    if (!nreset) begin
      ep_tx_q  <= {2 * L{NOSIG_SYM[7:0]}};
      ep_txk_q <= '1;
    end
    else begin
      ep_tx_q  <= ep_tx_data;
      ep_txk_q <= ep_tx_datak;
    end
  end
`else
  // the link: one register stage each way, idle (NOSIG) in reset
  always_ff @(posedge pclk or negedge nreset) begin
    if (!nreset) begin
      {rc_rx_data, rc_rx_datak} <= {{2 * L{NOSIG_SYM[7:0]}}, {2 * L{1'b1}}};
      {ep_rx_data, ep_rx_datak} <= {{2 * L{NOSIG_SYM[7:0]}}, {2 * L{1'b1}}};
    end
    else begin
      {rc_rx_data, rc_rx_datak} <= {ep_tx_data, ep_tx_datak};
      {ep_rx_data, ep_rx_datak} <= {rc_tx_data, rc_tx_datak};
    end
  end
`endif

`ifdef SIM_PIPEX1
  // make WRAP=x1: the x1 Gen1 wrappers, RCPIPEx1__pcieVHost and
  // PIPEx1__pcieVHost (no gen2 input, no Gen2ClkSel: the rate stays Gen1)
  RCPIPEx1__pcieVHost #(
      .NodeNum   (2),  // 3.sw/a7rc/VUserMain2.cpp: the Artix-7 RC model
      .DataWidth (16)
  ) u_rc (
      .pclk               (pclk),
      .nreset             (nreset),
`else
  PIPExN__pcieVHost #(
      .NodeNum   (2),  // 3.sw/a7rc/VUserMain2.cpp: the Artix-7 RC model
      .EndPoint  (0),
      .Lanes     (L),
      .DataWidth (16)
  ) u_rc (
      .pclk               (pclk),
      .gen2               (rate_sel),
      .nreset             (nreset),
      .Gen2ClkSel         (rc_gen2),
`endif
      .RxData             (rc_rx_data),
      .RxDataK            (rc_rx_datak),
      .TxData             (rc_tx_data),
      .TxDataK            (rc_tx_datak),
      .pipe_dn_pclk       (),
      .pipe_dn_data       (),
      .pipe_dn_datak      (),
      .pipe_up_pclk       (),
      .pipe_up_data       (),
      .pipe_up_datak      (),
      .dll_clk            (pclk),
      .dll_rx_data        (),
      .dll_rx_tlp_valid   (),
      .dll_rx_tlp_first   (),
      .dll_rx_tlp_last    (),
      .dll_rx_hdr_credit  (),
      .dll_rx_data_credit (),
      .dll_rx_update_type (),
      .dll_rx_packet_type (),
      .dll_rx_dllp_valid  (),
      .dllp_clk           (),
      .dllp_dn_data       (),
      .dllp_dn_valid      (),
      .dllp_up_data       (),
      .dllp_up_valid      (),
      .tx_clk             (),
      .tx_tlp_data        (),
      .tx_tlp_sop         (),
      .tx_tlp_eop         (),
      .tx_tlp_valid       (),
      .tx_peer_data       (),
      .tx_peer_sop        (),
      .tx_peer_eop        (),
      .tx_peer_valid      (),
      .rx_clk             (),
      .rx_tlp_data        (),
      .rx_tlp_sop         (),
      .rx_tlp_eop         (),
      .rx_tlp_valid       (),
      .rx_peer_data       (),
      .rx_peer_sop        (),
      .rx_peer_eop        (),
      .rx_peer_valid      ()
  );

`ifdef SIM_PIPEX1
  PIPEx1__pcieVHost #(
      .NodeNum   (1),  // usercode/VUserMain1.cpp: the endpoint model
      .EndPoint  (1),
      .DataWidth (16)
  ) u_ep (
      .pclk               (pclk),
      .nreset             (ep_nreset),
`else
  PIPExN__pcieVHost #(
      .NodeNum   (1),  // usercode/VUserMain1.cpp: the endpoint model
      .EndPoint  (1),
      .Lanes     (L),
      .DataWidth (16)
  ) u_ep (
      .pclk               (pclk),
      .gen2               (rate_sel),
      .nreset             (ep_nreset),
      .Gen2ClkSel         (),
`endif
      .RxData             (ep_rx_data),
      .RxDataK            (ep_rx_datak),
      .TxData             (ep_tx_data),
      .TxDataK            (ep_tx_datak),
      .pipe_dn_pclk       (),
      .pipe_dn_data       (),
      .pipe_dn_datak      (),
      .pipe_up_pclk       (),
      .pipe_up_data       (),
      .pipe_up_datak      (),
      .dll_clk            (pclk),
      .dll_rx_data        (),
      .dll_rx_tlp_valid   (),
      .dll_rx_tlp_first   (),
      .dll_rx_tlp_last    (),
      .dll_rx_hdr_credit  (),
      .dll_rx_data_credit (),
      .dll_rx_update_type (),
      .dll_rx_packet_type (),
      .dll_rx_dllp_valid  (),
      .dllp_clk           (),
      .dllp_dn_data       (),
      .dllp_dn_valid      (),
      .dllp_up_data       (),
      .dllp_up_valid      (),
      .tx_clk             (),
      .tx_tlp_data        (),
      .tx_tlp_sop         (),
      .tx_tlp_eop         (),
      .tx_tlp_valid       (),
      .tx_peer_data       (),
      .tx_peer_sop        (),
      .tx_peer_eop        (),
      .tx_peer_valid      (),
      .rx_clk             (),
      .rx_tlp_data        (),
      .rx_tlp_sop         (),
      .rx_tlp_eop         (),
      .rx_tlp_valid       (),
      .rx_peer_data       (),
      .rx_peer_sop        (),
      .rx_peer_eop        (),
      .rx_peer_valid      ()
  );

`ifdef WAVES
  // make WAVES=1: the waveform for WaveCrux (tb.fst; XSIM and JanusHDL write
  // tb.vcd, the Makefile converts it). Only the RC wrapper's own level: its
  // reset and rate, and its taps, which carry the link at the PIPE
  // (pipe_dn_*, pipe_up_*, lane 0), the DLLPs (dllp_*) and the TLPs (tx_*,
  // rx_*) both ways; the model below it would make the file many times
  // larger. Not tb itself: XSIM then drops the scopes below it.
`ifdef WAVES_X4
  // all four lanes, for the multi-lane PIPE and Data Link Layer decoders
  pipe_x4_view #(
      .DataWidth (16)
  ) pipe_view (
      .pclk (pclk),
      .dn   (rc_tx_data),
      .dnk  (rc_tx_datak),
      .up   (ep_tx_data),
      .upk  (ep_tx_datak)
  );
`endif
  initial begin
`ifdef WAVES_VCD
    $dumpfile("tb.vcd");
`else
    $dumpfile("tb.fst");
`endif
`ifdef WAVES_X4
    $dumpvars(1, pipe_view);
`endif
    $dumpvars(1, u_rc);
  end
`endif


endmodule : tb

// -----------------------------------------------------------------------------
// Project:     openPCIE_BFM
// Description: PCIE simulation model, built on pcieVHost
// Version:     1.0
// Date:        Nov 14, 2026
// -----------------------------------------------------------------------------
