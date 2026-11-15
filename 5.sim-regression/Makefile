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
#   make regress           the tester over seeds 1 to SEEDS
#   make sanity            the sanity list (run-sanity.sh), a few minutes
#   make regression        the regression list (run-regression.sh)
#   make clean             removes work/
#
# Everything a build or run makes goes to work/: work/<SIM>/<config>/ (the
# build, run.log), work/regress/<config>/<seed>/, work/logs/.
#
# SIM    verilator (default), icarus, xsim (Vivado), janushdl (jhdl)
# LANES  1 (default) or 4
# GEN    the fastest rate both sides advertise: 1 or 2 (default 2 at x1, 1 at x4)
# PHY    none (default): the models meet at the PIPE; core: the RC model is
#        the MAC (2.rtl/pipe_mac_adapter.sv) of a PIPE PHY (2.rtl/pipe_phy_core.sv)
# A7RC   0 (default): the RC model is a tester; 1: literal, only what the lab
#        RC sends
# WRAP   n (default): both nodes in PIPExN__pcieVHost; x1: RCPIPEx1__pcieVHost
#        and PIPEx1__pcieVHost (x1, Gen1 only)
# SEED   the tester's random stimulus (default 1), read at run time
# RUN_US time limit in us (default 2000)
# SEEDS  make regress: seeds 1 to SEEDS (default 10), REGRESS_JOBS at a time
#        (default 4), by ../4.build/regress.sh; Verilator or Icarus
#
# The VIP (VProc, pcieVHost, mem_model) is built once by ../4.build/build-vip.sh
# into ~/.cache/openPCIE_BFM/vip, with 1.upstream/patches/pcievhost-speed.patch and
# 1.upstream/patches/vproc-coroutine.patch.
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

SEEDS         ?= 10
REGRESS_JOBS  ?= 4
REGRESS_S     ?= 300
REGRESS_TRIES ?= 2
REGRESS_QUIET ?= 1

BFM        := $(abspath $(CURDIR)/..)
WORK       := $(CURDIR)/work
CFG         = $(WRAP).x$(LANES)g$(GEN).$(PHY)$(if $(filter 1,$(A7RC)),.a7rc)
OBJDIR      = $(WORK)/$(SIM)/$(CFG)

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
VIP_ENV     = VIP_PATCH=$(BFM)/1.upstream/patches/pcievhost-speed.patch \
              VPROC_PATCH=$(BFM)/1.upstream/patches/vproc-coroutine.patch
VIP_DIR    ?= $(shell $(VIP_ENV) bash $(BFM)/4.build/build-vip.sh)
export VIP_DIR

# ---- C/C++: the two programs, the checker, the LTSSM helper -------------------
#   usercode/VUserMain1.cpp  the endpoint (node 1)
#   3.sw/a7rc/VUserMain2.cpp      the Artix-7 RC model (node 2), 3.sw/a7rc/a7rc_check.cpp
#   3.sw/ltssm/ltssm.c            link training, for both
OPTFLAG    ?= -O2 -g
CPPSTD      = -std=c++20
INCLPATHS   = -I$(CURDIR)/usercode -I$(BFM)/3.sw/a7rc -I$(VIP_DIR)/include
DEFS        = -DVPROC -DEXCLUDE_LTSSM -DEP_GEN=$(GEN) -DRC_GEN=$(GEN) -DA7RC_LITERAL=$(A7RC) \
              -DLANE_REV_EP=1 -DLANE_REV_RC=0
ifeq ($(SIM),icarus)
  ICA_INC   = $(dir $(shell command -v $(IVERILOG)))../include/iverilog
  ICA_LIB   = $(dir $(shell command -v $(IVERILOG)))../lib
  DEFS     += -DICARUS -I$(ICA_INC)
else
  DEFS     += -DVPROC_SV
endif
USER_SRC    = $(CURDIR)/usercode/VUserMain1.cpp $(BFM)/3.sw/a7rc/VUserMain2.cpp $(BFM)/3.sw/a7rc/a7rc_check.cpp \
              $(BFM)/3.sw/ltssm/ltssm.c
VOBJS       = $(addprefix $(OBJDIR)/,$(patsubst %.cpp,%.o,$(patsubst %.c,%.o,$(notdir $(USER_SRC)))))
USERLIB     = $(OBJDIR)/libuser.a

# ---- HDL ----------------------------------------------------------------------
# The models' sources in compile order. Verilator and XSIM read every file of
# 2.rtl/ (but mem_model.sv: nothing here instantiates it), so the self-test
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
              $(BFM)/2.rtl/pipe_sym_pkg.sv \
              $(if $(USE_XN),$(BFM)/2.rtl/pcieVHostPipexN.sv $(BFM)/2.rtl/PIPExN__pcieVHost.sv) \
              $(if $(USE_X1),$(BFM)/2.rtl/PIPEx1__pcieVHost.sv $(BFM)/2.rtl/RCPIPEx1__pcieVHost.sv) \
              $(if $(or $(HDL_ALL),$(filter core,$(PHY))),$(BFM)/2.rtl/pipe_phy_core.sv $(BFM)/2.rtl/pipe_mac_adapter.sv) \
              $(if $(HDL_ALL),$(BFM)/2.rtl/pipe_x4_view.sv) \
              $(CURDIR)/tb.sv
HDL_DEFS    = VPROC_BYTE_ENABLE SIM_LANES=$(LANES) RUN_US=$(RUN_US) $(if $(filter core,$(PHY)),SIM_PIPE_PHY) \
              $(if $(filter x1,$(WRAP)),SIM_PIPEX1) $(if $(filter-out icarus,$(SIM)),VPROC_SV)

# =============================================================================
.PHONY: all run all-sims regress sanity regression clean help FORCE
.DEFAULT_GOAL := all

$(OBJDIR):
	@mkdir -p $@/hex

$(OBJDIR)/%.o: $(CURDIR)/usercode/%.cpp | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/%.o: $(BFM)/3.sw/a7rc/%.cpp | $(OBJDIR)
	@$(HOST_CXX) -c -fPIC -MMD -MP $(OPTFLAG) $(CPPSTD) -Wno-write-strings $(DEFS) $(INCLPATHS) $< -o $@

$(OBJDIR)/%.o: $(BFM)/3.sw/ltssm/%.c | $(OBJDIR)
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
	@mkdir -p $(WORK)/logs; for s in verilator icarus xsim janushdl; do \
	    t0=$$(date +%s); \
	    if $(MAKE) --no-print-directory SIM=$$s run > $(WORK)/logs/$$s.make.log 2>&1; then r=PASS; else r=FAIL; fi; \
	    echo "$$s: $$r, $$(( $$(date +%s) - t0 )) s (work/logs/$$s.make.log)"; \
	done

# The tester over seeds 1 to SEEDS, each in work/regress/<config>/<seed>/
regress: all
	@[ -n "$(filter verilator icarus,$(SIM))" ] || { echo "make regress: SIM=verilator or icarus"; exit 1; }
	@bash $(BFM)/4.build/regress.sh $(SEEDS) $(REGRESS_JOBS) $(REGRESS_S) $(REGRESS_TRIES) $(REGRESS_QUIET) \
	    $(WORK)/regress/$(SIM).$(CFG) "" -- $(SIM_CMD)

sanity:
	@bash run-sanity.sh

regression:
	@bash run-regression.sh

help:
	@sed -n '/^# openPCIE_BFM/,/^# ====/p' Makefile

clean:
	@rm -rf $(WORK)

# -----------------------------------------------------------------------------
# Project:     openPCIE_BFM
# Description: PCIE simulation model, built on pcieVHost
# Version:     1.0
# Date:        Nov 14, 2026
# -----------------------------------------------------------------------------

# Header dependencies of the user objects (-MMD -MP)
-include $(wildcard $(OBJDIR)/*.d)
