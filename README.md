# Pearl (PRL) miner — one-click install for office PCs

One file. Double-click `INSTALL-AND-MINE.bat` on a PC and it installs and starts
mining Pearl to Kryptex, then keeps it running across reboots.

## What it does

1. asks for administrator (needed for the power limit and the startup task)
2. downloads **SRBMiner-MULTI 3.7.6** from the official GitHub release
3. checks it against the published MD5 `550077549bf6da5ff1e1383d0ffd3a6f`
4. detects the GPU and tells you whether it can mine Pearl at all
5. sets the card to **70% of its factory power limit** (less heat, less wear)
6. registers a scheduled task so mining starts at every logon
7. starts mining immediately

Everything goes into `C:\MinePRL`. Nothing else on the machine is touched.

## Requirements — read this before rolling it out

**Pearl only runs on AMD and NVIDIA.** From SRBMiner's own algorithm list:

```
[2.00%]   [ -  A  N  - ]   pearlhash
                 A = AMD, N = NVIDIA, I = Intel (absent = not supported)
```

| GPU | Can mine Pearl? | 70% power limit? |
|---|---|---|
| **NVIDIA** (GTX 10-series and newer) | yes | **yes** |
| **AMD** (Radeon) | yes | **no CLI option** — see below |
| **Intel** integrated | **NO** | n/a |

**Most office PCs are Intel-HD only. Those cannot mine Pearl — the installer will
say so and stop without installing anything.** Check with `dxdiag` or Device
Manager before you walk round ten machines.

### AMD note
SRBMiner's `--gpu-plimit0` is **NVIDIA only**. On an AMD card the miner runs at
the driver default. To get 70% there, set it once in AMD Software →
Performance → Tuning → Power Limit `-30%`.

## Usage

```
Double-click INSTALL-AND-MINE.bat
```

Check it worked:

```
type C:\MinePRL\logs\miner-<date>.log
```

You want to see `Connected to prl-eu.kryptex.network:7048` and eventually
`share accepted`.

## Stop / start / remove

```bat
schtasks /end    /tn PearlMiner        :: stop now
schtasks /run    /tn PearlMiner        :: start now
schtasks /delete /tn PearlMiner /f     :: remove autostart
```

Then delete `C:\MinePRL` to remove everything.

## Important limitations, stated plainly

**1. The autostart fires at LOGON, not at boot.**
If a power cut leaves the PC on the lock screen, mining waits until somebody logs
in. There is no way around that without either storing a password for a service
account or enabling automatic logon — both are security decisions I am not making
for you. If these machines sit unattended, enabling automatic logon is the usual
answer.

**2. 70% power means less hashrate.**
That is the point — it is your call, but expect roughly 70–80% of the card's
full-power hashrate.

**3. The power limit is applied by SRBMiner at start, and it PERSISTS.**
Once set, the card keeps the 70% limit after the miner exits, until something sets
it back. That is the intended behaviour here, but worth knowing.

**4. Old cards earn very little.**
Pearl needs tensor-core-class throughput to be worthwhile. A GT 730 or a Radeon
R7 will mine a few TH/s at best. With free solar the electricity is not the issue,
but do not expect a second RTX-3070's worth of income from ten office PCs.

**5. Everything mines to one wallet.**
Worker names are the computer name, so all ten machines are distinguishable on
the pool page under the same address.

## What was tested

- download + MD5 verification: **passes**
- extraction: **passes**
- 220 W card → 154 W (70%): **calculated and passed to the miner**
- scheduled task registration (elevated): **passes** — `RunLevel: Highest`,
  `LogonType: Interactive`, trigger `MSFT_TaskLogonTrigger`
- GPU detection: **passes** (correctly reports an RTX 3070; virtual display
  adapters are filtered out)

## What was NOT tested

- A full run **on an office PC** with an old/AMD card. Only verified on the RTX
  3070 this was built from.
- The `--gpu-plimit0` value actually taking effect on a different card model.
  Verify with `nvidia-smi --query-gpu=power.limit --format=csv` after first run.
- Behaviour across an actual power cut + reboot. The task is registered correctly,
  but the logon dependency means it needs a person (or automatic logon) to fire.

## Credit

Miner: [SRBMiner-Multi](https://github.com/doktor83/SRBMiner-Multi) by doktor83 —
downloaded from the official release, never bundled here, so you always get a
version whose fingerprint you can check.
