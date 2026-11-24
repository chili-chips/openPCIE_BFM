SIM ?= verilator
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/../../2.rtl/openPCIE_BFM_pkg.sv $(PWD)/../../2.rtl/pipe_phy_core.sv
TOPLEVEL = pipe_phy_core
MODULE = test_pipe_phy_core
ifeq ($(SIM),verilator)
  EXTRA_ARGS += --timing -Wno-WIDTH -Wno-lint -Wno-style $(PWD)/dpi_stubs.cpp
endif
include $(shell cocotb-config --makefiles)/Makefile.sim
