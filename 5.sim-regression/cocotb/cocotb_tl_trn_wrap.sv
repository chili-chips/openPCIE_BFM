// SPDX-FileCopyrightText: 2026 NK Verif Labs
// SPDX-FileCopyrightText: 2026 CHILI.CHIPS.LLC
//
// SPDX-License-Identifier: BSD-3-Clause

module cocotb_tl_trn_wrap
  import tl_pkg::*;
  import trn_pkg::*;
  import dll_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [2:0]  dl_state_i,
    input  logic        rx_valid_i,
    input  logic        rx_first_i,
    input  logic        rx_last_i,
    input  logic        rx_half_i,
    input  logic        tx_ready_i,
    input  logic [63:0] rx_data_i,
    output logic        tx_valid_o,
    output logic        tx_first_o,
    output logic        tx_last_o,
    output logic        tx_half_o,
    output logic [63:0] tx_data_o,
    input  logic        fc_valid_i,
    input  logic [1:0]  fc_pkt_type_i,
    input  logic [1:0]  fc_class_i,
    input  logic [7:0]  fc_hdr_i,
    input  logic [11:0] fc_data_i,
    input  logic [63:0] trn_td_i,
    input  logic        trn_tsof_i,
    input  logic        trn_teof_i,
    input  logic        trn_tsrc_rdy_i,
    input  logic        trn_rdst_rdy_i,
    output logic        trn_tdst_rdy_o,
    output logic        trn_rrem_o,
    output logic        trn_rsof_o,
    output logic        trn_reof_o,
    output logic        trn_rsrc_rdy_o,
    output logic        trn_lnk_up_o,
    output logic [63:0] trn_rd_o
);
  dll_if    u_dll ();
  trn_tx_if u_trn_tx ();
  trn_rx_if u_trn_rx ();
  cfg_if    u_cfg ();

  assign u_dll.dl_state     = dl_state_e'(dl_state_i);
  assign u_dll.tx_tlp_ready = tx_ready_i;
  assign u_dll.rx_tlp       = '{valid: rx_valid_i, first: rx_first_i, last: rx_last_i, half: rx_half_i, data: rx_data_i};
  assign u_dll.rx_dllp      = '{valid: fc_valid_i, packet_type: dllp_type_e'(fc_pkt_type_i), update_type: fc_class_e'(fc_class_i), cred: '{hdr: fc_hdr_i, data: fc_data_i}};
  assign tx_valid_o         = u_dll.tx_tlp.valid;
  assign tx_first_o         = u_dll.tx_tlp.first;
  assign tx_last_o          = u_dll.tx_tlp.last;
  assign tx_half_o          = u_dll.tx_tlp.half;
  assign tx_data_o          = u_dll.tx_tlp.data;

  tl_top u_tl (
      .clk    (clk),
      .rst_n  (rst_n),
      .dll    (u_dll),
      .trn_tx (u_trn_tx),
      .trn_rx (u_trn_rx),
      .cfg    (u_cfg)
  );

  trn_compat u_trn (
      .trn_tx        (u_trn_tx),
      .trn_rx        (u_trn_rx),
      .trn_td        (trn_td_i),
      .trn_tsof      (trn_tsof_i),
      .trn_teof      (trn_teof_i),
      .trn_tsrc_rdy  (trn_tsrc_rdy_i),
      .trn_tdst_rdy  (trn_tdst_rdy_o),
      .trn_tbuf_av   (),
      .trn_trem      (1'b0),
      .trn_tsrc_dsc  (1'b0),
      .trn_terrfwd   (1'b0),
      .trn_tstr      (1'b0),
      .trn_tecrc_gen (1'b0),
      .trn_rd        (trn_rd_o),
      .trn_rrem      (trn_rrem_o),
      .trn_rsof      (trn_rsof_o),
      .trn_reof      (trn_reof_o),
      .trn_rsrc_rdy  (trn_rsrc_rdy_o),
      .trn_rdst_rdy  (trn_rdst_rdy_i),
      .trn_rsrc_dsc  (),
      .trn_rerrfwd   (),
      .trn_recrc_err (),
      .trn_rbar_hit  (),
      .trn_lnk_up    (trn_lnk_up_o),
      .dll_up        (dl_state_i == 3'd3),
      .clk           (clk),
      .rst_n         (rst_n)
  );
endmodule
