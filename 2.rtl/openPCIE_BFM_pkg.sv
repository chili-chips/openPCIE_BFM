// SPDX-FileCopyrightText: 2026 Chili.CHIPS
// SPDX-FileCopyrightText: 2004-2025 Simon Southwell (the values: pcieVHost, VProc, mem_model)
//
// SPDX-License-Identifier: GPL-3.0-or-later

//==========================================================================
// openPCIE_BFM * PCIE simulation model, built on pcieVHost
//--------------------------------------------------------------------------
// Description:
//   Everything the models share, typed: it replaces pcieVHost's, VProc's
//   and mem_model's `include headers and their `define macros
//   (pciexpress_header, pcie_vhost_map, test_defs, timescale, vprocdefs,
//   vprocdpi, extradefs, mem_model_dpi). Compile it first. No `timescale:
//   the simulator's command line gives it.
//
//   The C side keeps its own headers (pcie_vhost_map.h ...): the register
//   map below must match pcie_vhost_map.h.
//
//   One tool split: Icarus has no DPI-C, so the C models are reached
//   through VPI system tasks there (`__ICARUS__, Icarus's own predefined
//   name); every other simulator imports the DPI-C functions.
//==========================================================================

package openPCIE_BFM_pkg;

  //------------------------------------------------------------------------
  // Line symbols
  //------------------------------------------------------------------------

  // a 10-bit symbol on the serial line, in line order: the first bit in bit 0
  typedef bit [9:0] sym10_t;

  typedef enum sym10_t {
    SYM_IDLE  = '0,               // electrical idle: no symbol, a constant line
    SYM_COM_N = 10'b0101111100,   // K28.5, RD-
    SYM_COM_P = 10'b1010000011,   // K28.5, RD+
    SYM_SKP_N = 10'b0010111100,   // K28.0, RD-
    SYM_SKP_P = 10'b1101000011    // K28.0, RD+
  } sym10_e;

  function automatic bit is_com(input sym10_t s);
    return (s == SYM_COM_N) || (s == SYM_COM_P);
  endfunction

  function automatic bit is_skp(input sym10_t s);
    return (s == SYM_SKP_N) || (s == SYM_SKP_P);
  endfunction

  // electrical idle on a PIPE, per symbol: the K flag and 0xFF, which has
  // no 8b/10b code (upstream's NOSIG)
  localparam logic [8:0] NOSIG_SYM = {1'b1, 8'hFF};   // {K, byte}

  //------------------------------------------------------------------------
  // pcieVHost's VProc register map: the addresses its C model reads and
  // writes (pcie_vhost_map.h; ours: the taps, 210 to 217)
  //------------------------------------------------------------------------
  typedef enum bit [31:0] {
    LINKADDR0          = 0,    LINKADDR1  = 1,  LINKADDR2  = 2,  LINKADDR3  = 3,
    LINKADDR4          = 4,    LINKADDR5  = 5,  LINKADDR6  = 6,  LINKADDR7  = 7,
    LINKADDR8          = 8,    LINKADDR9  = 9,  LINKADDR10 = 10, LINKADDR11 = 11,
    LINKADDR12         = 12,   LINKADDR13 = 13, LINKADDR14 = 14, LINKADDR15 = 15,
    NODENUMADDR        = 200,
    LANESADDR          = 201,
    PVH_INVERT         = 202,
    EP_ADDR            = 203,
    CLK_COUNT          = 204,
    LINK_STATE         = 205,
    RESET_STATE        = 206,
    DISABLE_SCRAMBLING = 207,
    DISABLE_8B10B      = 208,
    GEN2_CLK           = 209,
    TAP_TLP_TX_SOP     = 210,
    TAP_TLP_TX         = 211,
    TAP_TLP_TX_EOP     = 212,
    TAP_TLP_RX_SOP     = 213,
    TAP_TLP_RX         = 214,
    TAP_TLP_RX_EOP     = 215,
    TAP_DLLP_TX        = 216,
    TAP_DLLP_RX        = 217,
    PVH_STOP           = 32'hFFFF_FFFD,
    PVH_FINISH         = 32'hFFFF_FFFE,
    PVH_FATAL          = 32'hFFFF_FFFF
  } pvh_reg_e;

  //------------------------------------------------------------------------
  // VProc: the access word VSched returns (VPRW) and its tick value
  //------------------------------------------------------------------------
  localparam int VP_WE_BIT    = 0;    // write
  localparam int VP_RD_BIT    = 1;    // read
  localparam int VP_BLK_LSB   = 2;    // burst length, 13:2
  localparam int VP_BLK_MSB   = 13;
  localparam int VP_BE_LSB    = 14;   // byte enables, 17:14
  localparam int VP_BE_MSB    = 17;
  localparam int VP_LBE_LSB   = 18;   // last byte enables of a burst, 21:18
  localparam int VP_LBE_MSB   = 21;
  localparam int VP_DELTA     = -1;   // ticks: a delta cycle, call again
  localparam int VP_DONTCARE  = 0;

  //------------------------------------------------------------------------
  // The C models: VProc (VInit, VSched, VIrq, VAccess) and mem_model
  // (MemModelRead, MemModelWrite). Tasks, so each simulator calls them the
  // same way
  //------------------------------------------------------------------------
`ifdef __ICARUS__

  task vp_init(input int node);
    $vinit(node);
  endtask

  task vp_sched(input int node, input int data_in, output int data_out, output int addr,
                output int rw, output int ticks);
    $vsched(node, data_in, data_out, addr, rw, ticks);
  endtask

  task vp_irq(input int node, input int irq);
    $virq(node, irq);
  endtask

  task vp_access(input int node, input int idx, input int data_in, output int data_out);
    $vaccess(node, idx, data_in, data_out);
  endtask

  task mem_read(input int address, output int data, input int be);
    $memread(address, data, be);
  endtask

  task mem_write(input int address, input int data, input int be);
    $memwrite(address, data, be);
  endtask

`else

  import "DPI-C" function void VInit(input int node);
  import "DPI-C" function void VSched(input int node, input int VPDataIn, output int VPDataOut,
                                      output int VPAddr, output int VPRw, output int VPTicks);
  import "DPI-C" function void VAccess(input int node, input int idx, input int VPDataIn,
                                       output int VPDataOut);
  import "DPI-C" function void VIrq(input int node, input int irq);
  import "DPI-C" function void MemModelRead(input int address, output int data, input int be);
  import "DPI-C" function void MemModelWrite(input int address, input int data, input int be);

  task vp_init(input int node);
    VInit(node);
  endtask

  task vp_sched(input int node, input int data_in, output int data_out, output int addr,
                output int rw, output int ticks);
    VSched(node, data_in, data_out, addr, rw, ticks);
  endtask

  task vp_irq(input int node, input int irq);
    VIrq(node, irq);
  endtask

  task vp_access(input int node, input int idx, input int data_in, output int data_out);
    VAccess(node, idx, data_in, data_out);
  endtask

  task mem_read(input int address, output int data, input int be);
    MemModelRead(address, data, be);
  endtask

  task mem_write(input int address, input int data, input int be);
    MemModelWrite(address, data, be);
  endtask

`endif

endpackage : openPCIE_BFM_pkg

// -----------------------------------------------------------------------------
// Project:     openPCIE_BFM
// Description: PCIE simulation model, built on pcieVHost
// Version:     1.0
// Date:        Nov 23, 2026
// -----------------------------------------------------------------------------
