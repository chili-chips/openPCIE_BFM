# SPDX-FileCopyrightText: 2026 Chili.CHIPS
#
# SPDX-License-Identifier: BSD-3-Clause

# =============================================================================
# openPCIE_BFM self-test: the Artix-7 RC model (node 2) against the endpoint model
# (node 1), two pcieVHost nodes back to back on a PIPE link (tb.sv).
#
# Run FROM THIS FOLDER, on Linux or WSL:
#   make [SIM=...] run     build and run; exit 0 on RC MODEL RESULT: PASS
#   make all-sims          run on every simulator, one line each
#   make clean
#
# SIM    verilator (default), icarus, xsim (Vivado), janushdl (jhdl)
# LANES  1 (default) or 4
# GEN    the fastest rate both sides advertise: 1 or 2 (default 2 at x1, 1 at x4)
# PHY    none (default): the models meet at the PIPE; core: the RC model is
#        the MAC (hdl/pipe_mac_adapter.sv) of a PIPE PHY (hdl/pipe_phy_core.sv)
# A7RC   0 (default): the RC model is a tester; 1: literal, only what the lab
#        RC sends
# WRAP   n (default): both nodes in PIPExN__pcieVHost; x1: RCPIPEx1__pcieVHost
#        and PIPEx1__pcieVHost (x1, Gen1 only)
# SEED   the tester's random stimulus (default 1), read at run time
# RUN_US time limit in us (default 2000)
#
# The VIP (VProc, pcieVHost, mem_model) is built once by ../tools/build-vip.sh
# into ~/.cache/openPCIE_BFM/vip, with patches/pcievhost-speed.patch and
# patches/vproc-coroutine.patch.
# =============================================================================

SIM    ?= verilator
WRAP   ?= n
LANES  ?= 1
GEN    ?= $(if $(or $(filter 4,$(LANES)),$(filter x1,$(WRAP))),1,2)
PHY    ?= none
A7RC   ?= 0
SEED   ?= 1
RUN_US ?= 2000

ifeq ($(filter n x1,$(WRAP)),)
  $(error WRAP must be n or x1 (got "$(WRAP)"))
endif
ifeq ($(WRAP),x1)
  ifneq ($(LANES)$(GEN),11)
    $(error WRAP=x1 is x1 Gen1: LANES=1 GEN=1)
  endif
endif

ifeq ($(filter verilator icarus xsim janushdl,$(SIM)),)
  $(error SIM must be verilator, icarus, xsim or janushdl (got "$(SIM)"))
endif
ifeq ($(filter 1 4,$(LANES)),)
  $(error LANES must be 1 or 4 (got "$(LANES)"))
endif
ifeq ($(filter 1 2,$(GEN)),)
  $(error GEN must be 1 or 2 (got "$(GEN)"))
endif
ifeq ($(filter none core,$(PHY)),)
  $(error PHY must be none or core (got "$(PHY)"))
endif
ifeq ($(filter 0 1,$(A7RC)),)
  $(error A7RC must be 0 or 1 (got "$(A7RC)"))
endif

BFM        := $(abspath $(CURDIR)/..)
OBJDIR      = $(CURDIR)/obj/$(SIM).$(WRAP).x$(LANES)g$(GEN).$(PHY)$(if $(filter 1,$(A7RC)),.a7rc)

# ---- tools --------------------------------------------------------------------
HOST_CC    ?= gcc
HOST_CXX   ?= g++
HOST_AR    ?= ar
VERILATOR  ?= verilator
IVERILOG   ?= iverilog
VVP        ?= vvp
JHDL       ?= jhdl
XILINX_VIVADO ?= $(HOME)/Xilinx/2026.1/Vivado
XVLOG      ?= $(XILINX_VIVADO)/bin/xvlog
XELAB      ?= $(XILINX_VIVADO)/bin/xelab
XSIM       ?= $(XILINX_VIVADO)/bin/xsim

# ---- the VIP ------------------------------------------------------------------
VIP_ENV     = VIP_PATCH=$(BFM)/patches/pcievhost-speed.patch \
              VPROC_PATCH=$(BFM)/patches/vproc-coroutine.patch
VIP_DIR    ?= $(shell $(VIP_ENV) bash $(BFM)/tools/build-vip.sh)
export VIP_DIR

# ---- C/C++: the two programs, the checker, the LTSSM helper -------------------
#   usercode/VUserMain1.cpp  the endpoint (node 1)
#   a7rc/VUserMain2.cpp      the Artix-7 RC model (node 2), a7rc/a7rc_check.cpp
#   ltssm/ltssm.c            link training, for both
OPTFLAG    ?= -O2 -g
CPPSTD      = -std=c++20
INCLPATHS   = -I$(CURDIR)/usercode -I$(BFM)/a7rc -I$(VIP_DIR)/include
DEFS        = -DVPROC -DEXCLUDE_LTSSM -DEP_GEN=$(GEN) -DRC_GEN=$(GEN) -DA7RC_LITERAL=$(A7RC) \
              -DLANE_REV_EP=1 -DLANE_REV_RC=0
ifeq ($(SIM),icarus)
  ICA_INC   = $(dir $(shell command -v $(IVERILOG)))../include/iverilog
  ICA_LIB   = $(dir $(shell command -v $(IVERILOG)))../lib
  DEFS     += -DICARUS -I$(ICA_INC)
else
  DEFS     += -DVPROC_SV
endif
USER_SRC    = $(CURDIR)/usercode/VUserMain1.cpp $(BFM)/a7rc/VUserMain2.cpp $(BFM)/a7rc/a7rc_check.cpp \
              $(BFM)/ltssm/ltssm.c
VOBJS       = $(addprefix $(OBJDIR)/,$(patsubst %.cpp,%.o,$(patsubst %.c,%.o,$(notdir $(USER_SRC)))))
USERLIB     = $(OBJDIR)/libuser.a

# ---- HDL ----------------------------------------------------------------------
# The models' sources in compile order. Verilator and XSIM read every file of
# hdl/ (but mem_model.sv: nothing here instantiates it), so the self-test
# also compiles what it does not run. Icarus 14 and JanusHDL 0.17 get only
# what this run uses: neither parses pipe_mac_adapter.sv's assertions, and
# Icarus not PIPExN__pcieVHost.sv (an automatic variable in an always block)
HDL_ALL     = $(filter verilator xsim,$(SIM))
USE_XN      = $(or $(HDL_ALL),$(filter n,$(WRAP)))
USE_X1      = $(or $(HDL_ALL),$(filter x1,$(WRAP)))
HDL_INC     = $(VIP_DIR)/hdl/headers $(VIP_DIR)/hdl
HDL_SRC     = $(VIP_DIR)/hdl/headers/allheaders.svh \
              $(VIP_DIR)/hdl/f_VProc.sv \
              $(VIP_DIR)/hdl/clkmux.sv \
              $(VIP_DIR)/hdl/Serialiser.sv \
              $(VIP_DIR)/hdl/pcieVHost.sv \
              $(VIP_DIR)/hdl/pcieVHostPipex1.sv \
              $(BFM)/hdl/pipe_sym_pkg.sv \
              $(if $(USE_XN),$(BFM)/hdl/pcieVHostPipexN.sv $(BFM)/hdl/PIPExN__pcieVHost.sv) \
              $(if $(USE_X1),$(BFM)/hdl/PIPEx1__pcieVHost.sv $(BFM)/hdl/RCPIPEx1__pcieVHost.sv) \
              $(if $(or $(HDL_ALL),$(filter core,$(PHY))),$(BFM)/hdl/pipe_phy_core.sv $(BFM)/hdl/pipe_mac_adapter.sv) \
              $(if $(HDL_ALL),$(BFM)/hdl/pipe_x4_view.sv) \
              $(CURDIR)/tb.sv
HDL_DEFS    = VPROC_BYTE_ENABLE SIM_LANES=$(LANES) RUN_US=$(RUN_US) $(if $(filter core,$(PHY)),SIM_PIPE_PHY) \
              $(if $(filter x1,$(WRAP)),SIM_PIPEX1) $(if $(filter-out icarus,$(SIM)),VPROC_SV)

# =============================================================================
.PHONY: all run all-sims clean help FORCE
.DEFAULT_GOAL := all

$(OBJDIR):
	@mkdir -p $@/hex

$(OBJDIR)/%.o: $(CURDIR)/usercode/%.cpp | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/%.o: $(BFM)/a7rc/%.cpp | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/%.o: $(BFM)/ltssm/%.c | $(OBJDIR)
	@$(HOST_CC) -c -fPIC -MMD -MP $(OPTFLAG) $(DEFS) $(INCLPATHS) $< -o $@

$(USERLIB): $(VOBJS)
	@rm -f $@
	@$(HOST_AR) cr $@ $(VOBJS)

# ---- Verilator: one native executable, the models linked in (DPI-C) ----------
# CFG_LDFLAGS_VERILATED cleared: a Verilator built with mold links through it,
# and mold fails on network shares
ifeq ($(SIM),verilator)
SIMEXE      = $(OBJDIR)/Vtb
$(SIMEXE): $(USERLIB) FORCE
	@[ $(USERLIB) -nt $@ ] && rm -f $@; true
	@$(VERILATOR) --binary -sv --timing --top-module tb -Mdir $(OBJDIR) \
	    -Wno-fatal -Wno-WIDTH -Wno-lint -Wno-style \
	    $(addprefix +incdir+,$(HDL_INC)) $(addprefix +define+,$(HDL_DEFS)) $(HDL_SRC) \
	    -MAKEFLAGS "--quiet CFG_LDFLAGS_VERILATED=" -CFLAGS "$(CPPSTD) -Wno-attributes" \
	    -LDFLAGS "-Wl,-whole-archive $(USERLIB) -Wl,-no-whole-archive -L$(VIP_DIR)/lib -lcosimlnx -lpcielnx -lpthread -lrt -ldl -rdynamic"
SIM_CMD     = $(SIMEXE)
endif

# ---- Icarus: the models over VPI ---------------------------------------------
ifeq ($(SIM),icarus)
SIMEXE      = $(OBJDIR)/sim
$(OBJDIR)/VProc.vpi: $(USERLIB)
	@$(HOST_CXX) -shared -fPIC -pthread -rdynamic -o $@ \
	    -Wl,-whole-archive $(USERLIB) -Wl,-no-whole-archive \
	    -Wl,-whole-archive -L$(VIP_DIR)/lib -lpcieica -lcosimica -Wl,-no-whole-archive \
	    -L$(ICA_LIB) -lvpi -lrt -ldl
$(SIMEXE): $(OBJDIR)/VProc.vpi FORCE
	@$(IVERILOG) -g2012 -o $@ -s tb $(addprefix -I,$(HDL_INC)) $(addprefix -D,$(HDL_DEFS)) $(HDL_SRC)
SIM_CMD     = $(VVP) -n -M $(OBJDIR) -m VProc $(SIMEXE)
endif

# ---- XSIM and JanusHDL: the models as a DPI-C library, VProc.so ---------------
# xsim loads Vivado's own, older libstdc++ first: ours is linked in statically
ifneq ($(filter xsim janushdl,$(SIM)),)
$(OBJDIR)/VProc.so: $(USERLIB)
	@$(HOST_CXX) -shared -fPIC -rdynamic -static-libstdc++ -static-libgcc -o $@ \
	    -Wl,-whole-archive $(USERLIB) -Wl,-no-whole-archive \
	    -L$(VIP_DIR)/lib -lcosimlnx -lpcielnx -lpthread -lrt
endif

ifeq ($(SIM),xsim)
SIMEXE      = $(OBJDIR)/xsim.dir/tb/xsimk
$(SIMEXE): $(OBJDIR)/VProc.so FORCE
	@cd $(OBJDIR) && $(XVLOG) -sv --nolog $(addprefix -i ,$(HDL_INC)) $(addprefix --define ,$(HDL_DEFS)) $(HDL_SRC) > xvlog.out || { cat xvlog.out; exit 1; }
	@cd $(OBJDIR) && $(XELAB) --nolog -sv_root $(OBJDIR) -sv_lib VProc --timescale 1ps/1ps --snapshot tb work.tb > xelab.out || { cat xelab.out; exit 1; }
SIM_CMD     = $(XSIM) --nolog -R tb
endif

# JanusHDL compiles the sources at each run
ifeq ($(SIM),janushdl)
SIMEXE      = $(OBJDIR)/VProc.so
SIM_CMD     = $(JHDL) --top tb $(addprefix +incdir+,$(HDL_INC)) $(addprefix +define+,$(HDL_DEFS)) $(HDL_SRC) \
              --sv-lib $(OBJDIR)/VProc.so
endif

FORCE:

all: $(SIMEXE)

# Runs in $(OBJDIR), with hex/ContDisps.hex (the model's packet display). The
# exit code is 0 only on RC MODEL RESULT: PASS (xsim exits 0 after $fatal)
run: all
	@cp -f $(CURDIR)/hex/ContDisps.hex $(OBJDIR)/hex/
	@cd $(OBJDIR) && A7RC_SEED=$(SEED) $(SIM_CMD) 2>&1 | tee run.log; \
	grep -a -q 'RC MODEL RESULT: PASS' run.log

# Every simulator in turn, one line each: result and wall time
all-sims:
	@mkdir -p obj; for s in verilator icarus xsim janushdl; do \
	    t0=$$(date +%s); \
	    if $(MAKE) --no-print-directory SIM=$$s run > obj/$$s.make.log 2>&1; then r=PASS; else r=FAIL; fi; \
	    echo "$$s: $$r, $$(( $$(date +%s) - t0 )) s (obj/$$s.make.log)"; \
	done

help:
	@sed -n '/^# openPCIE_BFM/,/^# ====/p' Makefile

clean:
	@rm -rf $(CURDIR)/obj

# -----------------------------------------------------------------------------
# Project:     openPCIE_BFM
# Description: PCIE simulation model, built on pcieVHost
# Version:     1.0
# Date:        Nov 14, 2026
# -----------------------------------------------------------------------------

# Header dependencies of the user objects (-MMD -MP)
-include $(wildcard $(OBJDIR)/*.d)
