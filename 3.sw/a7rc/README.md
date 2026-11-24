# openPCIE_BFM: the Artix-7 RC model

The Artix-7 RC model: pcieVHost set up as the AMD `PCIE_2_1` root port, with the drivers in [`3.sw/a7rc/VUserMain2.cpp`](VUserMain2.cpp) and the checker in [`3.sw/a7rc/a7rc_check.cpp`](a7rc_check.cpp). It trains the link as the hard macro does, runs the RC firmware's requests and judges every TLP and DLLP against 59 rules.

## The Artix-7 RC model

### Calibrated against the hard macro

Speaking the same PCIE is not behaving the same: as the RC, pcieVHost runs its own LTSSM, timers and credits. To test our EP against the RC it meets in the lab, the model gets an Artix-7 RC profile, the way the [rv32 ISS](https://github.com/chili-chips/openCologne-PCIE/blob/main/5.sim/README.md#the-cpu-node-three-ways-to-run-the-socs-software) has timing models for PicoRV32 and eduBOS5:

1. **Measure.** On openPCIE, the `PCIE_2_1` RC drives the pcieVHost EP. Its PIPE, taps and LTSSM state show what the RC puts on the wire: training sequence counts and fields per LTSSM state, timeouts, speed change, InitFC credits, ACK and UpdateFC timing. Cases: direct, Gen1 x1 and Gen2 x1.
2. **Profile.** One table: behaviour, Artix-7 value, pcieVHost value.
3. **Model.** RC-only changes to pcieVHost (`ltssm.c` and the user code), picked by a profile switch. `ltssm.c` has one Configuration path for both roles, so an unguarded change moves the RC too.
4. **Check.** The same pcieVHost EP, against the profiled RC here and against the hard macro on openPCIE, must log the same link training and DLLP sequence.
5. **Use.** The profiled RC is the host of every openCologne-PCIE run, with full-length training ([below](https://github.com/chili-chips/openCologne-PCIE/blob/main/5.sim/README.md#the-host-openpcies-artix-7-rc-model)).

Limits: the hard macro's simulation model is not silicon (analog effects, CDR lock time), and a profile covers only what the openPCIE runs exercise.

The measurements behind it: [openPCIE, Our TB jig as a foundation for an accurate RC model](https://github.com/chili-chips/openPCIE/blob/main/5.sim/README.md#our-tb-jig-as-a-foundation-for-an-accurate-rc-model).

## Drive and check

The model drives the endpoint and judges what comes back, which no open-source project does yet ([the gap](https://github.com/chili-chips/openPCIE/blob/main/5.sim/README.md#open-source-pcie-validation-stacks)). The drivers are in [`VUserMain2.cpp`](VUserMain2.cpp). The checkers, in [`a7rc_check.cpp`](a7rc_check.cpp), see every TLP and DLLP on the link through our packet monitor in pcieVHost (`SetPktMonitor()`).

- **Two modes.** The default is the tester: the lab RC's sequence, then what its firmware never sends but the spec allows. `A7RC=1` is literal: only what the lab RC sends, with its timing. Up to the firmware's result both match the hard macro, as below. The checkers run in both. `make A7RC=1 WAVES=1 run` writes `work/waves/<SIM>.n.x1g2.none.a7rc.fst`.
- **Rules.** Each has an ID, prefixed by layer, and a section of the PCIe Base Specification 2.1. At the end the model prints checks and violations per rule; any violation fails the run. A FAIL, or no result by `RUN_US`, ends the sim with `$fatal`, so `make run` exits non-zero.
- **An error-free line.** Nothing corrupts symbols in simulation, so a Nak or a replay is the endpoint's fault, not noise.
- **Self-check.** The model checks its own TLPs too: framing, Length within MPS and MRRS, no 4 KB crossing. A violation there is a model error, and fails the run as well.
- **Seeds.** One seed drives the tester's random stimulus: `make run SEED=N` (default 1, no rebuild), `make regress SEEDS=N` for seeds 1 to N. With the [coroutine VProc](../../1.upstream/README.md#what-we-added) a seed takes under a second under Verilator. The model prints how often each kind of stimulus ran, so a seed that hits nothing shows; `make regress` ends with the rules no seed checked.
- **Mutants.** In openPCIE, `make mutants` breaks the endpoint one way at a time (no SKP, a reserved Training Control bit, one EIOS at 5.0 GT/s, a short electrical idle, Recovery.Speed at 2.5 GT/s without a faster common rate) and checks that each fails the rule it breaks: the checker's own regression.
- **Stuck Recovery.** A Recovery that runs 50 µs prints `---> Recovery for 50 us, still in RcvrLock ...` with the substate and rate, long before the run's time limit (expected after a failed speed change, or with openPCIE's `SIM_FAULT=linkdown`).

**Drivers**

| Driver | Mode | What it sends | Status |
|---|---|---|---|
| Lab RC sequence | both | link training with the Artix-7 TS counts and timing, FC init, then the RC firmware: ID read, BAR sizing and placement, Command, a write and a read at BAR0, with its think times | done |
| `CfgSweep()` | tester | every DW of 00h-FFh and the extended capability chain; all ones to read-only registers, ones to the RW1C status bits, each read back; a read of function 1 | done |
| `Stress()` | tester | 8 writes and 8 reads to BAR0 back to back (the spec sets no gap; only flow control limits the sender), the data checked | done |
| `Mix()`: request mix | tester | each BAR filled, then 64 writes and reads at random (`make MIX=N`, read at run time: sustained load, as a hardware BAR test; `MIX=1000` adds about 0.37 ms): 1 byte to MPS (writes) or MRRS (reads), any byte address, so partial Byte Enables; some end at a 4 KB boundary, none crosses one. `TL.ORDER` checks the data | done |
| `Mix()`: pacing | tester | back to back, a random gap, or a burst of 4-12; random free tags, up to 32 reads outstanding | done |
| `SlowAcks()` | tester | the RC Acks late but within the limit (3/4 of Table 3-7), with 24 reads outstanding: Completions stay on the wire longer than the endpoint's replay timer while every Ack advances; each must restart that timer, so any replay is a violation (`DL.REPLAY`). A pcieVHost endpoint whose Ack does not restart the timer fails `DL.REPLAY` | done |
| `Burst()` | tester | `BURST` posted 1-DW writes back to back (`make BURST=N`, default 64, 0 skips it; as a hardware write burst), paced only by the endpoint's posted credits, then the span read back (`TL.ORDER`). Its throughput is a probe line | done |
| `Burst()`: rounds | tester | `make BURST_ROUNDS=R`: R rounds of the burst, each but the last followed by a checked read; a flood as on a hardware test (16 writes × 8 rounds, 64 × 32) | done |
| Ack delay | tester and literal | `make ACK=N`: the RC Acks N symbol times after a TLP (default the profile's, 92 at x1, 64 at x4), a slower host; past the Ack latency limit (`ACK=1000`) the endpoint must replay | done; issue 70 open on the pcieVHost endpoint |
| Start-up offset | tester and literal | the RC stays electrically idle 0 to 100 µs after reset, by seed (none for seed 1), before it trains: the endpoint waits in Detect, as when a host rescans a card already up. `make START_US=N` sets it | done |
| `Unsupported()` | tester | IO read and write, MRdLk, a read and a write outside the BARs, a Type 1 Configuration Read, Vendor-Defined Messages Type 0 (UR) and Type 1 (dropped silently); Device Status cleared first, then checked after each group: set after a UR, kept by a 0, cleared by a 1, still clear after the Type 1 message; then an ordinary read | done |
| `Odd()` | tester | a write and a read with ECRC (TD 1); a poisoned write, then its read; a poisoned Configuration Write (UR, Interrupt Line unchanged); the error status; reads with Traffic Class 1-7 and Relaxed Ordering / No Snoop | done |
| `Faults()` | tester | Data Link faults from the RC, each around reads whose Completions must arrive once: a Nak of a good Completion, Acks held past the endpoint's replay timer, a TLP with a bad LCRC, a TLP sent again after its Ack (a duplicate), a DLLP with a bad CRC, the endpoint's next TLP lost (no Ack, no Nak: it replays on its timer), a nullified TLP (dropped, no Nak), a sequence number one ahead (Naked), a read with a bad ECRC (answered as usual: no AER), an Ack for a TLP never sent (a Data Link Protocol Error, Fatal) (`InjectFault()`, `SendDuplicate()`, `SendAck()`, our pcieVHost hooks; the stored copy stays good, so the replay is); then Device Status, Correctable and Fatal Error Detected | done |
| `Speed()` | tester | link speed changes the RC directs (`ChangeLinkSpeed()`), with 4 reads outstanding: to Gen1 and back to Gen2; the Completions may come before, in or after the Recovery (Gen2 links only) | done |
| `Retrain()` | tester | Recovery at 8 random points (`RetrainLink()`, or `ChangeLinkSpeed()` to a random rate when both sides advertise Gen2): 1 to 4 reads and some writes, then a random gap of up to 400 symbol clocks, so the endpoint's Completions and Acks are on the wire, queued or not yet due | done |
| `Dma()` | tester | the endpoint's own requests: the RC writes a trigger to Interrupt Line, and the endpoint program ([`ep_dma.h`](ep_dma.h)) writes 48 blocks of 64 bytes to the RC's memory and reads them back, the data compared; the RC holds its UpdateFCs for 10 µs (`HoldFc()`), so the endpoint runs out of posted credits and must wait | done |
| Credit starvation | tester | late UpdateFCs: done (`Dma()` holds the RC's for 10 us); minimum credits: planned | partly |
| Training varied | tester | from the seed (`SetLtssmVary()`): up to 8 more TS1/TS2 and idle symbols in Configuration and Recovery than the least, 0 to 2 more EIOS, up to 128 ns more idle in Recovery.Speed | done |
| Lane polarity | openPCIE: `SIM_POLARITY=1` | both serial lines inverted: each receiver inverts its lane | done |
| Lane reversal | openPCIE: `SIM_LANES=4 SIM_LANE_REVERSE=1` | the x4 lanes wired reversed; the endpoint (`SIM_LANE_REV=ep`), the RC model (`rc`, tester only) or both may reverse; Recovery at random points: `Retrain()`; a Gen1-only RC: `SIM_RC_GEN=1`. Here, `LANES=4` wires the lanes straight; the endpoint may reverse (`LANE_REV_EP=1`) | done |
| `SEED=N` | tester | one reproducible seed for all random stimulus; `make regress SEEDS=N`, each seed with a time limit and retries | done |

**Checkers** (the endpoint's side of the link)

| Rule | PCIe 2.1 | Checks |
|---|---|---|
| `TL.FMT-TYPE` | 2.2.1, 1.3.2.2 | Fmt/Type defined; Message routing an endpoint may use; no I/O request from a PCI Express Endpoint (a Legacy Endpoint may) |
| `TL.RSVD` | 2.2.1 | reserved header bits 0; TH, IDO, AT 0 (not enabled) |
| `TL.LENGTH` | 2.2.2, 2.2.7 | Length matches the payload; payload <= MPS (128 B), read <= MRRS (512 B) |
| `TL.ECRC` | 2.7.1 | no ECRC from the endpoint: without AER its generation is off, also on Completions to requests with ECRC |
| `TL.POISON` | 2.7.2.2 | EP 1 only on a TLP with data (poisoning data is legal) |
| `TL.REQ-ID` | 2.2.6.2 | the endpoint's requests carry its captured bus/device |
| `TL.REQ-ADDR` | 2.2.4.1 | address bits 1:0 0; 64-bit format only above 4 GB |
| `TL.REQ-4KB` | 2.2.7 | no request crosses 4 KB |
| `TL.REQ-BE` | 2.2.5 | First/Last DW Byte Enables legal for the Length |
| `TL.REQ-BME` | 7.5.1.1 | the endpoint's memory and I/O requests only with Bus Master Enable set |
| `TL.CPL-MATCH` | 2.3.2 | a Completion for an outstanding request: Requester ID, Tag |
| `TL.CPL-ID` | 2.2.9 | Completer ID: the bus/device captured from the Type 0 CfgWr |
| `TL.CPL-STATUS` | 2.2.9 | status defined; CRS only for Cfg; data only with SC, for reads |
| `TL.CPL-FIELDS` | 2.2.9, 2.3.1.1 | Byte Count, Lower Address, Length, BCM 0; a split ends on the completer's RCB, 128 bytes (the Link Control RCB bit is the Root Port's) |
| `TL.CPL-TC-ATTR` | 2.2.9 | TC and Attr as the request's |
| `TL.CPL-ALL` | 2.3.1 | every non-posted request completed |
| `TL.ORDER` | 2.4.1 | a read returns what the RC wrote before it, or after it (a posted write may pass a read); enabled bytes only |
| `DL.DLLP-CRC` | 3.4.1 | DLLP CRC good |
| `DL.DLLP-TYPE` | 3.4.1 | DLLP type defined, VC0 only |
| `DL.NAK` | 3.5.3.1 | no Nak, but after a TLP the RC sent with a bad LCRC |
| `DL.LCRC` | 3.5.2.1 | LCRC good, or inverted with EDB |
| `DL.SEQ` | 3.5.2.1 | sequence numbers from 0, one up per new TLP |
| `DL.REPLAY` | 3.5.2.1 | a replay only after a Nak from the RC, or once the replay timer ran out: timed from the oldest unAcked TLP's transmission or the last Ack that advanced, the TLPs after it in the same replay with it; and an unAcked TLP sent again within twice the timer (+100%) |
| `DL.ACK-SEQ` | 3.5.2.2 | an Ack or Nak names a TLP sent, never an older one |
| `DL.ACK-LAT` | 3.5.3.1 | each TLP Acked within the Ack latency limit, in L0 time: the table value (no tolerance, unlike the replay timer), plus a TLP in progress, the Ack itself and the link |
| `DL.DLLP-RSVD` | 3.4.1 | DLLP reserved fields 0 |
| `DL.REPLAY-ORDER` | 3.5.2.1 | a replay starts at the oldest unAcked TLP (after a Nak, the one after its) and goes in order, before any new TLP |
| `DL.BAD-TLP` | 3.5.3.1 | a TLP with a bad LCRC is Naked with the last good sequence number, and dropped |
| `DL.DUPLICATE` | 3.5.3.1 | a duplicate TLP (sent again after its Ack) is Acked within the Ack latency limit, not Naked, and dropped (no Completion: `TL.CPL-MATCH`) |
| `FC.INIT-ORDER` | 3.3.1 | InitFC1, then InitFC2 (FI1 may end an InitFC1 set early), then UpdateFC once FC_INIT2 can be done; each set P, NP, Cpl in order |
| `FC.INIT-SAME` | 2.6.1.2 | InitFC2 credits equal InitFC1 |
| `FC.INFINITE` | 2.6.1 | an UpdateFC of an infinite type carries 0 |
| `FC.FORWARD` | 2.6.1.2 | a credit limit never moves back |
| `FC.RANGE` | 2.6.1 | at most 127 header and 2047 data credits ahead |
| `FC.UPDATE-PERIOD` | 2.6.1.2 | an UpdateFC of each finite type at most 30 µs +50% apart |
| `FC.TLP-EARLY` | 3.3.1 | no TLP before the endpoint can have left FC_INIT2: its own InitFC2 sent, or the RC's sent |
| `FC.EP-CREDITS` | 2.6.1.1 | the endpoint's TLPs fit the RC's credits |
| `FC.INIT-MIN` | 2.6.1 | initial data credits: Posted and Completion at least Max_Payload_Size Supported, Non-Posted at least 1, or infinite |
| `FC.CPL-INF` | 2.6.1 | an endpoint advertises infinite Completion credits |
| `FC.RETURN` | 2.6.1.2 | by the end, UpdateFCs returned every credit the RC's TLPs used (an expectation, not a spec rule: the run idles 45 µs first) |
| `CFG.ID` | 7.5.1 | Vendor ID neither FFFFh nor 0000h |
| `CFG.HEADER` | 7.5.1.2 | Header Type 0, Latency Timer 0, Capabilities List 1, Capabilities Pointer >= 40h; reserved bits 0 |
| `CFG.CAP-LIST` | 7.6 | the capability chain ends, no loop; PM and PCIe Capabilities present |
| `CFG.PCIE-CAP` | 7.8.2, 7.8.3 | PCIe Capability version 2 (2.1 hardwires 2h; 1 accepted for a 1.x device at 2.5 GT/s), Endpoint, no slot; MPS Supported defined; Role-Based Error Reporting set, as by every function of PCIe 1.1 on |
| `CFG.LINK` | 7.8.6, 7.8.8 | Link Capabilities speed and width defined; Link Status = the trained link |
| `CFG.EXT-CAPS` | 7.9.1 | the extended capability chain from 100h ends (all 0 if none) |
| `CFG.BAR` | 7.5.2.1 | a BAR read after all ones: type defined, size mask contiguous |
| `CFG.RO` | 7.4 | read-only bits keep their value across a write |
| `CFG.RW1C` | 7.4 | RW1C bits that were 1 read 0 after a write of 1, and stay 1 after a write of 0 |
| `CFG.FN` | 7.3.3 | a request to a function a single-function device lacks gets UR |
| `PL.FRAMING` | 4.2.2 | no K symbol inside a packet; a DLLP is 8 symbols and ends in END |
| `PL.L0-ONLY` | 4.2.6.4 | no TLP or DLLP from the endpoint's first TS1/TS2 of a training or Recovery until it can be in L0: the RC back in L0, or 16 symbol times and a DLLP after the RC began Configuration.Idle or Recovery.Idle |
| `PL.SPEED` | 4.2.6.4.3 | a speed change up only in a Recovery whose TS2s from the endpoint carried speed_change, to a rate they advertised (down to 2.5 GT/s: also the fallback, 4.2.6.4.2) |
| `PL.TS-FIELDS` | 4.2.4.1 | TS1/TS2: Data Rate bit 1 set, bits 0 and 3-5 0, speed_change not in Polling or Configuration, the same rates there; Training Control 0 but Disable Scrambling (bits 5-7 reserved; the RC directs no Hot Reset, Disable, Loopback or Compliance Receive); after Configuration, the Link and Lane Numbers it set |
| `PL.SKP` | 4.2.7.1 | SKP Ordered Sets: in Polling, Configuration and L0 never more than 1538 + Max_Payload_Size + 28 Symbol Times apart (4.2.7.2); in L0 one per 1180 to 1538 (give or take one per L0 period) |
| `PL.EIOS` | 4.2.4.2 | EIOS from the endpoint, lane 0: only in Recovery, on the way to Recovery.Speed (after TS2s with speed_change, at 2.5 GT/s with 5.0 GT/s on both sides; or, at 5.0 GT/s or back from a changed rate, after RcvrLock timed out with TS1 only, 4.2.6.4.1, or in RcvrCfg, after its TS2, once the RC sent EIOS, 4.2.6.4.3); one at 2.5 GT/s, two in a row at 5.0 GT/s; at least 32 TS2s with speed_change before (counted from its first); then electrically idle until the RC is, and for at least 800 ns after the later EIOS, 6 µs without speed_change (4.2.6.4.2) |
| `TL.UR` | 2.3.1 | an unsupported non-posted request gets UR, a supported one never |
| `TL.CRS` | 2.3.1 | CRS only until the first successful Configuration Completion |
| `CFG.ERR-STATUS` | 6.2.5, 6.2.3.2.4, 7.8.5, 7.5.1.2 | Device Status by Figure 6-2 (no AER): a posted request's UR sets UR Detected and Non-Fatal Error Detected; a non-posted one's with Role-Based Error Reporting is Advisory: no severity bit, UR Detected set or clear accepted (the figure and 7.8.5 differ); a poisoned posted request: Non-Fatal, or none as Advisory; Bad TLP, Bad DLLP, Replay Timer Timeout: Correctable Error Detected; Fatal never; Status Detected Parity Error on every poisoned request |

The `PL.` rules see the ordered sets on lane 0 of an x1 link (the RC model's), and the RC's LTSSM state, not the endpoint's; `PL.SPEED` judges the speed at each return to L0.

**Results.** Against the pcieVHost endpoint here and the EP model in openCologne-PCIE, all 59 rules pass in both modes, at the PIPE, on the serial line and through the speed changes; in openCologne-PCIE under Verilator and Icarus, and over 100 seeds. The first runs found three deviations in the EP model and a bug in pcieVHost's Configuration Requests ([issues 14 to 16](../../1.upstream/README.md#simulation-issues)). The request mix, the unsupported requests, `-O0`/`-O2` builds with UBSan and valgrind, the odd requests (ECRC, poisoned, TC 1-7), the Data Link faults and independent reviews of the code found forty-six more in pcieVHost: Completions over Max_Payload_Size, Acks and UpdateFCs held behind queued TLPs, accesses refused at a BAR's end or a 4 KB boundary, no RW1C bits, no UR Detected, MRdLk completed by an endpoint, an array one word short, an uninitialised counter in link training, poisoned TLPs taken as good, Completions without the request's TC and attributes, ECRC on by default, no replay timer, no duplicate detection, a Nak with the wrong sequence number, no Data Link Protocol Error, a packet display that rewrote the CRCs it checked, a crash on a packet shorter than its header, SKP Ordered Sets held back by a busy queue or through training, a serial receiver that lost its symbol alignment after electrical idle, no lane polarity inversion, electrical idle hidden at the PIPE, X on the line at start-up, a race one symbol wide between simulators, and Configuration that checked lane 0 only at any width ([issues 17 to 69](../../1.upstream/README.md#simulation-issues), 38, 47, 51, 54, 62, 65 and 66 ours). All are fixed or worked around but one limitation we keep. `TL.CRS` is exercised only with openPCIE's `SIM_FAULT=crs`. The faults and the DMA print what they did: here (seed 1) one Nak from the RC, 19 TLPs sent again in 5 replays, 96 endpoint requests with its posted header credits down to 0.

**The checker against broken endpoints.** `make mutants` ([`4.build/mutants.py`](../../4.build/mutants.py)) breaks the endpoint model one way at a time, each in its own copy of the repo, and each run must fail the rule it breaks. Shared by this repo, openPCIE and openCologne-PCIE (`make mutants` in each). The `PL.EIOS` mutants need a Gen2 speed change, `pl-eios-gen1` also openPCIE's `SIM_SPEED_TEST`; elsewhere they print n/a.

| Mutant | The endpoint model | Must fail |
|---|---|---|
| `pl-skp` | sends no SKP Ordered Set | `PL.SKP` |
| `pl-ts-fields` | a reserved Training Control bit set | `PL.TS-FIELDS` |
| `pl-eios-count`, `-idle`, `-lock`, `-gen1` | one EIOS at any rate; idle too short; RcvrLock gives up early at Gen2; Recovery.Speed without 5.0 GT/s | `PL.EIOS` |
| `dl-lcrc` | a TLP with a bad LCRC | `DL.LCRC` |
| `dl-dllp-crc` | a DLLP with a bad CRC | `DL.DLLP-CRC` |
| `dl-nak` | Naks a good TLP | `DL.NAK` |
| `dl-ack-lat` | Acks 5000 ticks late | `DL.ACK-LAT` |
| `dl-dup` | sends a TLP again, with no Nak and no timeout | `DL.REPLAY` |
| `fc-update` | no UpdateFC for 50000 ticks | `FC.UPDATE-PERIOD` |

All 11 that apply here fail their rule (2026-11-23), and all 8 that apply in openCologne-PCIE (Gen1).

**The endpoint probe.** Every run ends with `===> Probe:` lines: the endpoint's Data Link timing as the RC sees it, with the link, under the tester's faults. It is openPCIE's `HM_PROBE` turned around: the RC model measures any endpoint. A line shows min to max, the count, and the limit. Ack latency counts the oldest TLP each Ack covers, in L0 all along. Today, x1, seed 1:

| Probe | pcieVHost EP, here (Gen2) | EP model, openCologne-PCIE (Gen1) | our GateMate EP, openCologne-PCIE `A7RC=1` (Gen1) | Limit |
|---|---|---|---|---|
| Ack latency | 84-172 ns Gen1, 40-334 ns Gen2 | 128-716 ns | 720-752 ns | 1688 ns Gen1, 996 ns Gen2, with the link (3.5.3.1) |
| bad LCRC to Nak | 40 ns | 128 ns | no fault (`A7RC=1`) | the Ack latency limit |
| duplicate to Ack | 40 ns | 128 ns | no fault | the Ack latency limit |
| RC Nak to replay | 70 ns | 188 ns | no fault | none: the link and a TLP |
| replay timer, no Nak | 1776-1920 ns (Gen2) | 2940-3228 ns | no fault | 2844 ns Gen1, 1728 ns Gen2, -0%/+100% (3.5.2.1) |
| UpdateFC period | up to 15.0 µs | up to 30.1 µs | up to 31.0 µs | 45 µs: 30 µs +50% (2.6.1.2) |
| read: MRd END to the first CplD END | 62 ns at Gen2, 124 ns at Gen1 (min: a single read) | not measured | not measured | none; max with reads queued |
| posted burst from the RC (1-DW writes) | 83.0 MB/s at Gen2, 41.5 at Gen1 (`BURST=2400`): 100% of the link | not measured | not measured | 83.3 MB/s Gen2, 41.7 Gen1, framing only |

Our EP's tester run, with the faults, ends at the 10 ms limit before the probe prints (openCologne-PCIE [#9](https://github.com/chili-chips/openCologne-PCIE/issues/9)).

**How it runs in openPCIE.** [`tb_rc.sv`](https://github.com/chili-chips/openPCIE/blob/main/5.sim/tb_rc.sv) puts the model in place of the RC_opensource DUT, against the same pcieVHost endpoint (`VUserMain1.cpp`), on a 16-bit x1 PIPE. Resets as in `tb.sv`: PERST# at 1 µs, the endpoint 487 ns later. No RTL, no CPU: the run takes seconds.

- [`VUserMain2.cpp`](VUserMain2.cpp): the model, pcieVHost on node 2. It sets the profile's values, trains the link, starts flow control, then runs our RC firmware ([`3.sw/RC-direct`](https://github.com/chili-chips/openPCIE/blob/main/3.sw/RC-direct)) ported to C++: the ID read, `assign_bars()` (Command off, size each BAR, place it in the window from 0x80000000 or park it), Command on, then the self-test write and read at BAR0. Same Requester ID (0x10EE), bus 1, tags, CRS retry and result markers (`0x0000FACE`: pass).
- Firmware time: each request leaves the hard macro's measured time after the endpoint's last TLP (8.996-14.46 µs, by the firmware's code path), plus about 1 µs at Gen1. The first one 80.958 µs after the model's own L0: the SOC leaves reset at DL_Active, so a late endpoint delays it ([Fault tests](https://github.com/chili-chips/openPCIE/blob/main/5.sim/README.md#fault-tests-the-firmwares-error-paths)). The Completion timeout (2.18 ms) and the CRS retry (374 µs) are the firmware's too. `GetLinkTimeNs()` (`ltssm.c`) counts the time at both rates. It checks every Completion (tag, Requester ID, status, byte count) and the values the firmware reads.
- `SetLinkProfile(LTSSM_PROFILE_ARTIX7_RC)` in `ltssm.c`: the RC's Configuration path. Link and Lane numbers at once, 8 more TS1 in Linkwidth.Accept and Lanenum.Accept, the Autonomous Change bit in Configuration.Complete. The default, `LTSSM_PROFILE_EP`, is the endpoint as before.
- Gen2 (openPCIE's `SIM_GEN=2`, the default; here `GEN=2`, the default at x1): both sides advertise Gen2, and the model starts the change to Gen2 right after InitFC2, as the Artix-7 RC does (1.95 µs after L0). The RC sets the rate: in Recovery.Speed, with both sides idle, the profile writes pcieVHost's `GEN2_CLK` register. Its `Gen2ClkSel` output (now a port of `PIPExN__pcieVHost`) switches the clocks of `tb_rc.sv`.
- openPCIE's `SIM_SPEED_TEST=1`: the endpoint takes the link to Gen1 at the firmware's BAR0 write and back at its BAR1 write. Both changes meet traffic; the model holds its Ack for the BAR0 Completion through Recovery, as the hard macro does (5.520 µs).

Against the hard macro (`tb.x1g1.direct.fst`; the change to Gen2 from `tb.x1g2.direct.fst`), RC transmit as the endpoint sees it:

| Item | Hard macro | RC model |
|---|---|---|
| Before Polling | electrical idle; the first TS1 3.035 µs after PERST# (4.035 µs) | the same: 4.040 µs |
| Disable Scrambling bit in every TS | set: the sim build turns scrambling off (`SIM_PIPE_CODING`) | the same (`CONFIG_LTSSM_TS_CTL`) |
| Configuration TS1, Link = 0: Lane = PAD / Lane = 0 | 15 / 14 | the same |
| Configuration.Complete TS2, Autonomous Change | 24 | the same |
| Configuration.Idle SKP, after the last TS2 starts | 280 ns | 285 ns |
| Last training TS (L0) | 74.099 µs | 74.120 µs |
| N_FTS, credits | 255; P 32/437, NP 12/24 | the same |
| Last training TS to the first InitFC | 657 ns | the same |
| InitFC: DLLP spacing, round, InitFC1 / InitFC2 rounds | 64 ns, 192 ns, 5 / 4 | the same |
| SKP during training | 12, one every 92 TS, the last in Configuration.Idle | the same |
| Ack after the END of an endpoint TLP | 424 ns at Gen1, 212 ns at Gen2 (median); one per TLP | the same |
| Requests: 21, the firmware's order and headers | Gen2: the first 80.958 µs after L0 (155.057 µs); each after the endpoint's last TLP | the same: the first at 155.076 µs, each gap within 8 ns; the last request 0.25 µs later |
| The same at Gen1 | 81.032 µs after L0; each about 1 µs longer, except two: Command = 0 (+812 ns), Command = 6 (+0) | each gap within 40 ns, except those two; the last request 1.6 µs later |
| Change to Gen2 starts, after the last training TS | 2.368 µs, right after InitFC2 | 2.360 µs |
| First UpdateFC, after the end of InitFC; then | 32.77 µs; every 32.77 µs | the same |

The speed changes of openPCIE's `make SIM_SPEED_TEST=1` (`tb.x1g2.direct.speed.fst`, `tb.x1g2.model.speed.fst`), RC transmit, hard macro / RC model:

| Phase | RC starts Gen1→Gen2 | EP starts Gen2→Gen1 | EP starts Gen1→Gen2 |
|---|---|---|---|
| RcvrLock TS1, old rate (with Speed Change) | 13 (12) / 13 (12) | 16 (8) / 16 (8) | 17 (8) / 16 (8) |
| RcvrCfg TS2, old rate | 32 / 32 | 34 / 34 | 34 / 33 |
| Idle, last EIOS to the first TS1 at the new rate | 866 / 856 ns | 1194 / 1200 ns | 858 / 850 ns |
| RcvrLock TS1, new rate | 14 / 17 | 24 / 24 | 15 / 16 |
| RcvrCfg TS2, new rate | 17 / 16 | 17 / 16 | 17 / 16 |
| First TS1 to last TS2 | 4.87 / 4.77 µs | 5.41 / 5.31 µs | 5.18 / 4.99 µs |

EIOS counts compare since the PIPE PHY model keeps the line idle under TxElecIdle ([issue 54](../../1.upstream/README.md#simulation-issues)): 2 at Gen2, 1 at Gen1, on both. A fixed model bug: when the EP's EIOS came first, the model changed the rate before its own EIOS reached the EP, so the EP waited out its 6 µs idle timeout.

## On the serial line

In openPCIE, `make run RC=model IFACE=serial` runs the same model on a 1-bit line per lane each way (x1, or x4 with `SIM_LANES=4`), in [`tb_rc_serial.sv`](https://github.com/chili-chips/openPCIE/blob/main/5.sim/tb_rc_serial.sv): both sides are upstream's `PcieVhostSerial` ([`pcieVHost.sv`](../../1.upstream/vip/pcievhost/verilog/pcieVHost/pcieVHost.sv), with `Serialiser.sv` and `clkmux.sv` from its `verilog/lib`). The C model does 8b/10b and scrambling, as on hardware, and the Disable Scrambling bit is clear. Electrical idle is a constant 0 on the line. This is the level the GateMate SerDes BFM takes.

- `Gen2Clk = 1`: the wrappers take the Gen2 clocks (500 MHz, 5 GHz) and halve them at Gen1; `GEN2_CLK` selects. (Upstream's `generate` drove the bit clock twice with `Gen2Clk = 0`: issue 58.)
- Each side switches its own clocks, so the endpoint profile now writes `GEN2_CLK` in Recovery.Speed too. On a PIPE its `Gen2ClkSel` is left open.
- Gen2 and Gen1 PASS; the Gen2 run changes the link to Gen2 on the serial line.
- openPCIE's `USRSIMOPTS="--define DUMP_VCD"` dumps each side's 10-bit symbols and transaction taps (`tb.x1g2.model.serial.fst`); add `--define DUMP_LINE` for the 1-bit line, a few G events a second.

RC transmit, PIPE / serial: the same sequence. The endpoint now sees the RC's electrical idle and starts training at 4.03 µs (1.51 µs on the PIPE), so the counts the RC takes from its partner shift a little:

| Item | PIPE | Serial |
|---|---|---|
| First training TS | 4.040 µs | 4.025 µs |
| Polling.Active TS1 | 17 | 18 |
| Configuration TS1 Lane = PAD / Lane = 0, TS2 | 15 / 14, 24 | the same |
| Last training TS (L0) | 74.120 µs | 74.041 µs |
| First InitFC, Gen2 change, after L0 | 657 ns, 2.360 µs | 634 ns, 2.324 µs |
| DLLPs: InitFC1 / InitFC2 rounds, UpdateFC P / NP, Ack | 5 / 4, 8 / 8, 20 | the same |
| TLPs | 21 | 21 |

The Artix-7's own serial timing (its GTP: latency, electrical idle, receiver detection) is not measured: the model puts its PIPE behaviour on an ideal serialiser.

## Driving another project's EP

openCologne-PCIE runs this model as the only host of its co-simulation, against its GateMate EP RTL (`make run EP=rtl`) and its EP model (`EP=model`), at the PIPE or, with `IFACE=serial`, on the serial line, through Cologne Chip's PIPE logic and the GateMate SerDes BFM ([its 5.sim README](https://github.com/chili-chips/openCologne-PCIE/tree/main/5.sim#the-host-openpcies-artix-7-rc-model)). It takes from [openPCIE_BFM](https://github.com/chili-chips/openPCIE_BFM), as openPCIE does, `VUserMain2.cpp`, `a7rc_check.cpp` and `.h`, `ltssm.c`, `pcievhost-speed.patch` and `vproc-coroutine.patch`; what it expects of that EP, IDs and BAR sizes, comes from there (`-DA7RC_EP_EXPECT`). With `-DA7RC_PIPE_SCRAMBLE` it scrambles at the PIPE too, as the lab RC: openCologne-PCIE sets it for its EP RTL.

- The model starts the change to Gen2 only when the EP advertised Gen2, as the Artix-7 RC does; the GateMate EP is Gen1.
- Its first run found two EP issues: one InitFC set of each kind (legal; the model completes FC init on it, upstream's pcieVHost hangs), and an UpdateFC-NP that lowered the header limit from 32 to 9 after the first Configuration Read (the model stops, PCIe 2.1, 2.6.1). With the second fixed there, the run passes, at the PIPE and on the serial line.
- In the tester mode, the EP Naks every TLP after the first of a back-to-back run: 58 Naks for 16 TLPs. The first Nak crashed pcieVHost ([issue 13](../../1.upstream/README.md#simulation-issues)); with that fixed, the replays deliver all 16, and the data checks.

--------------------
#### End of Document
