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
//   Self-test on the serial line (make IFACE=serial): the same two nodes as
//   tb.sv, each in PcieVhostSerial (8b/10b and scrambling on, as on
//   hardware), a line per lane each way, x1 or x4, Gen1 or Gen2.
//
//        u_rc  PcieVhostSerial, EndPoint = 0   <-- the Artix-7 RC model, node 2
//          |   a line per lane each way: 2.5 or 5 Gb/s
//        u_ep  PcieVhostSerial, EndPoint = 1   <-- the endpoint model, node 1
//
//   Each side has its own clocks: the endpoint's are PPM ppm off the RC's
//   (make PPM; + faster), as two boards with their own reference clocks
//   (SRNS). RX_RETIME (make RETIME, default 1): the receivers
//   recover the bits from the line and keep a SKP buffer (Serialiser,
//   RX_RETIME); 0: they sample on their own clock, and with PPM not 0 the
//   link fails. The endpoint drives each lane as a pair: its N
//   (LinkOutN) is the inverse of P, or 0 with it in electrical idle.
//
//   The run ends when the RC model has checked the endpoint (RC MODEL
//   RESULT), or at the time limit RUN_US. Every setting is a parameter (the
//   Makefile sets them per simulator); no macros.
//==========================================================================


// One side's clocks, PPM off nominal: the Gen2 bit clock (5 GHz; the
// wrapper halves it at Gen1) and the symbol clock, a tenth of it. Each edge
// at its exact time, k half periods, so the rounding to the time precision
// (10 ps) does not add up. A clock generator: its delays are the model's time
module tb_ser_clocks #(
    parameter real PPM = 0.0
) (
    output bit serclk,
    output bit clk
);

  initial begin : edges
    longint k;
    real    half;
    serclk = 1'b0;
    clk    = 1'b0;
    half   = 0.1 / (1.0 + PPM * 1.0e-6);   // ns
    k      = 0;
    forever begin
      k = k + 1;
      #((k * half - $realtime) * 1ns);
      serclk = ~serclk;
      if ((k % 10) == 0) clk = ~clk;
    end
  end

endmodule : tb_ser_clocks

// The file holds tb, as tb.sv: every simulator's top is tb (Makefile)
// verilog_lint: waive module-filename
module tb #(
    parameter int  LANES     = 1,     // make LANES: 1 or 4
    parameter int  RUN_US    = 2000,  // make RUN_US: the time limit
    parameter real PPM       = 0.0,   // make PPM: the endpoint's clocks, ppm off the RC's
    parameter int  RX_RETIME = 1,     // make RETIME: the receivers recover the bits
    parameter bit  WAVES     = 0,     // make WAVES=1: the waveform
    parameter bit  WAVES_VCD = 0      // ... as VCD (XSIM, JanusHDL), else FST
);

  localparam int L = LANES;

  bit rc_serclk, rc_clk, ep_serclk, ep_clk;
  bit nreset;     // PERST#: the RC model
  bit ep_nreset;  // the endpoint, a little later

  tb_ser_clocks #(.PPM(0.0))      u_rc_clk (.serclk(rc_serclk), .clk(rc_clk));
  tb_ser_clocks #(.PPM(PPM))      u_ep_clk (.serclk(ep_serclk), .clk(ep_clk));

  initial begin
    nreset    = 1'b0;
    ep_nreset = 1'b0;
    $display("tb_serial: %0d lane(s), endpoint %0.0f ppm, RX_RETIME %0d", L, PPM, RX_RETIME);
    #(1us) nreset <= 1'b1;
    #(487ns) ep_nreset <= 1'b1;
    #(RUN_US * 1us - 1us - 487ns);
    $fatal(1, "time limit of %0d us: no RC MODEL RESULT", RUN_US);
  end

  //------------------------------------------------------------------------
  // The lines: lane l to lane l, each way. The endpoint's pair: P and N
  //------------------------------------------------------------------------
  logic [15:0] rc_out, ep_out, ep_out_n;
  logic [15:0] rc_in, ep_in;

  for (genvar l = 0; l < 16; l++) begin : g_lane
    if (l < L) begin : g_used
      assign ep_in[l] = rc_out[l];
      assign rc_in[l] = ep_out[l];
    end else begin : g_unused
      assign ep_in[l] = 1'b0;
      assign rc_in[l] = 1'b0;
    end
  end

  // lane 0, for the waveform: electrical idle is ser_up_p = ser_up_n = 0
  logic ser_dn, ser_up_p, ser_up_n;
  assign ser_dn   = rc_out[0];
  assign ser_up_p = ep_out[0];
  assign ser_up_n = ep_out_n[0];

  // a pair is P = ~N in data, P = N = 0 in electrical idle; never P = N = 1.
  // Sampled on the endpoint's bit clock: P and N change together at its edge
  always @(posedge u_ep.SerClkOut) begin : pair_check
    if ((ser_up_p === 1'b1) && (ser_up_n === 1'b1)) begin
      $fatal(1, "endpoint lane 0: P = N = 1");
    end
  end

  //------------------------------------------------------------------------
  // The RC model and the endpoint
  //------------------------------------------------------------------------
  PcieVhostSerial #(
      .LinkWidth (L),
      .NodeNum   (2),             // 3.sw/a7rc/VUserMain2.cpp: the Artix-7 RC model
      .EndPoint  (0),
      .Gen2Clk   (1),
      .RX_RETIME (RX_RETIME)
  ) u_rc (
      .Clk       (rc_clk),
      .SerClk    (rc_serclk),
      .notReset  (nreset),
      .ClkOut    (),
      .SerClkOut (),
      .LinkIn0   (rc_in[0]),   .LinkIn1   (rc_in[1]),   .LinkIn2   (rc_in[2]),   .LinkIn3   (rc_in[3]),
      .LinkIn4   (rc_in[4]),   .LinkIn5   (rc_in[5]),   .LinkIn6   (rc_in[6]),   .LinkIn7   (rc_in[7]),
      .LinkIn8   (rc_in[8]),   .LinkIn9   (rc_in[9]),   .LinkIn10  (rc_in[10]),  .LinkIn11  (rc_in[11]),
      .LinkIn12  (rc_in[12]),  .LinkIn13  (rc_in[13]),  .LinkIn14  (rc_in[14]),  .LinkIn15  (rc_in[15]),
      .LinkOut0  (rc_out[0]),  .LinkOut1  (rc_out[1]),  .LinkOut2  (rc_out[2]),  .LinkOut3  (rc_out[3]),
      .LinkOut4  (rc_out[4]),  .LinkOut5  (rc_out[5]),  .LinkOut6  (rc_out[6]),  .LinkOut7  (rc_out[7]),
      .LinkOut8  (rc_out[8]),  .LinkOut9  (rc_out[9]),  .LinkOut10 (rc_out[10]), .LinkOut11 (rc_out[11]),
      .LinkOut12 (rc_out[12]), .LinkOut13 (rc_out[13]), .LinkOut14 (rc_out[14]), .LinkOut15 (rc_out[15]),
      .LinkOutN  ()
  );

  PcieVhostSerial #(
      .LinkWidth (L),
      .NodeNum   (1),             // usercode/VUserMain1.cpp: the endpoint
      .EndPoint  (1),
      .Gen2Clk   (1),
      .RX_RETIME (RX_RETIME)
  ) u_ep (
      .Clk       (ep_clk),
      .SerClk    (ep_serclk),
      .notReset  (ep_nreset),
      .ClkOut    (),
      .SerClkOut (),
      .LinkIn0   (ep_in[0]),   .LinkIn1   (ep_in[1]),   .LinkIn2   (ep_in[2]),   .LinkIn3   (ep_in[3]),
      .LinkIn4   (ep_in[4]),   .LinkIn5   (ep_in[5]),   .LinkIn6   (ep_in[6]),   .LinkIn7   (ep_in[7]),
      .LinkIn8   (ep_in[8]),   .LinkIn9   (ep_in[9]),   .LinkIn10  (ep_in[10]),  .LinkIn11  (ep_in[11]),
      .LinkIn12  (ep_in[12]),  .LinkIn13  (ep_in[13]),  .LinkIn14  (ep_in[14]),  .LinkIn15  (ep_in[15]),
      .LinkOut0  (ep_out[0]),  .LinkOut1  (ep_out[1]),  .LinkOut2  (ep_out[2]),  .LinkOut3  (ep_out[3]),
      .LinkOut4  (ep_out[4]),  .LinkOut5  (ep_out[5]),  .LinkOut6  (ep_out[6]),  .LinkOut7  (ep_out[7]),
      .LinkOut8  (ep_out[8]),  .LinkOut9  (ep_out[9]),  .LinkOut10 (ep_out[10]), .LinkOut11 (ep_out[11]),
      .LinkOut12 (ep_out[12]), .LinkOut13 (ep_out[13]), .LinkOut14 (ep_out[14]), .LinkOut15 (ep_out[15]),
      .LinkOutN  (ep_out_n)
  );

  if (WAVES) begin : g_dump
    initial begin
      $dumpfile(WAVES_VCD ? "tb.vcd" : "tb.fst");
      $dumpvars(1, tb);
    end
  end : g_dump


endmodule : tb

// -----------------------------------------------------------------------------
// Project:     openPCIE_BFM
// Description: PCIE simulation model, built on pcieVHost
// Version:     1.0
// Date:        Nov 23, 2026
// -----------------------------------------------------------------------------
