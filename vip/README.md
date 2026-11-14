# Co-simulation VIP: upstream copies

The files of the [wyvernSemi](https://github.com/wyvernSemi) models this BFM builds, with LF line endings and the changes [`../tools/vip-import.sh`](../tools/vip-import.sh) applies (VProc byte-enable ports left open, `` `fatal`` calls `tb.Fatal`, the transaction taps, `.sv`/`.svh` names). GPL-3.0-or-later, by Simon Southwell (each folder has its `LICENSE`).

| Folder | Upstream | Version |
|---|---|---|
| `vproc` | [wyvernSemi/vproc](https://github.com/wyvernSemi/vproc) | `VERSION_1_13_4` (8fa7a6d) |
| `pcievhost` | [wyvernSemi/pcievhost](https://github.com/wyvernSemi/pcievhost) | `VESRSION_1_9_3` (sic, 77d6462) |
| `mem_model` | [wyvernSemi/mem_model](https://github.com/wyvernSemi/mem_model) | `main` c7b9c62 |

Only the files the build uses are here; docs and examples stay upstream. [`../tools/build-vip.sh`](../tools/build-vip.sh) builds them, with [`../patches`](../patches) applied.

To upgrade: set the new version in [`../tools/vip-import.sh`](../tools/vip-import.sh), run it, update this table, run the self-test on every simulator.

--------------------
#### End of Document
