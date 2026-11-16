# LTSSM support code for _pcieVHost_

This source code in this directory is a _partial_ implementation model of the PCIE LTSSM link training state machine. It is incomplete but can power up from electrically idle to the link up L0 state.

It is not part of the _pcievhost_ proper and sits on top of the API provided by the model. It can be used by the user code and, in this repo's self-test is compiled into the `libuser.a` library that `5.sim-regression/Makefile` builds (in `work/<SIM>/<config>/`), along with the user-provided source code.