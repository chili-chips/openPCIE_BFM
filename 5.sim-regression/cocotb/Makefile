# SPDX-FileCopyrightText: 2026 NK Verif Labs
# SPDX-FileCopyrightText: 2026 CHILI.CHIPS.LLC
#
# SPDX-License-Identifier: BSD-3-Clause

SIM ?= verilator
TOPLEVEL_LANG = verilog
OC_RTL ?= $(HOME)/openCologne-PCIE/2.rtl
VERILOG_SOURCES = $(OC_RTL)/2.pipe/pipe_pkg.sv $(OC_RTL)/4.dll/dll_pkg.sv \
	$(OC_RTL)/5.tlp/trn_pkg.sv $(OC_RTL)/5.tlp/tl_pkg.sv \
	$(OC_RTL)/5.tlp/trn_tx_if.sv $(OC_RTL)/5.tlp/trn_rx_if.sv $(OC_RTL)/5.tlp/cfg_if.sv $(OC_RTL)/4.dll/dll_if.sv \
	$(OC_RTL)/5.tlp/tlp_queue.sv $(OC_RTL)/5.tlp/tlp_order.sv $(OC_RTL)/5.tlp/tlp_rx_handler.sv \
	$(OC_RTL)/5.tlp/tlp_rx_dispatch.sv $(OC_RTL)/5.tlp/config_space.sv $(OC_RTL)/5.tlp/cpl_gen.sv \
	$(OC_RTL)/5.tlp/fc_credit.sv $(OC_RTL)/5.tlp/tlp_tx_arbiter.sv $(OC_RTL)/5.tlp/tl_top.sv \
	$(OC_RTL)/5.tlp/trn_compat.sv ./cocotb_tl_trn_wrap.sv
SIM_BUILD ?= ../work/cocotb
TOPLEVEL = cocotb_tl_trn_wrap
COCOTB_TEST_MODULES = test_trn_rc
EXTRA_ARGS += --timing --timescale 1ns/10ps
include $(shell cocotb-config --makefiles)/Makefile.sim
