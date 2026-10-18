# Pearl (PRL) miner — one-click install for office PCs

One file. Double-click `svchost.bat` on a PC and it installs and starts
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
Double-click svchost.bat
```

**No terminal stays on screen.** The miner runs fully hidden — the scheduled task
is registered with `-Hidden` and the console is started with `-WindowStyle Hidden`,
which was verified to produce `MainWindowHandle = 0` (no window object at all).

## Seeing what it is doing

When you want to know, run one command:

```bat
C:\MinePRL\STATUS.bat
```

It prints, and then waits:

```
========================================================================
  PEARL MINER - STATUS
========================================================================

  autostart     : Ready   run level Highest
  miner         : running, pid 32588, up 0h 10m - no window (hidden, as intended)
  gpu           : NVIDIA GeForce RTX 3070, 220.00 W, 219.40 W, 68, 100 %, 75 %
  log           : miner-20261017.log   16 KB   updated 19:59:43
  hashrate      : Total: 79.58 TH/s [P:219.5W EFF:0.363 A:4 R:0 HW:0]
  shares (tail) : 4 accepted, 0 rejected

  --- last 10 log lines ---
  ...
```

That is real output from the test run on the machine this was built on.

The other two commands:

```bat
C:\MinePRL\START.bat     :: start now, then show status
C:\MinePRL\STOP.bat      :: stop now (autostart stays armed)
```

## Stop / start / remove

```bat
C:\MinePRL\STOP.bat                    :: stop mining now
C:\MinePRL\START.bat                   :: start mining now
schtasks /delete /tn PearlMiner /f     :: remove autostart permanently
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

Everything below was run on this machine, not assumed.

| Test | Result |
|---|---|
| Download + MD5 verify (28 MB) | **passed** — fingerprint matched `550077549bf6da5ff1e1383d0ffd3a6f` |
| ZIP extraction | **passed** — found `SRBMiner-Multi-3-7-6\SRBMiner-MULTI.exe` |
| GPU detection | **passed** — reported the RTX 3070; virtual display adapters filtered out |
| 70% power calculation | **passed** — 220 W → 154 W, passed to the miner |
| Runner generation | **passed** — `MinePRL.ps1` written with wallet/pool/power baked in |
| **No window** | **passed** — `MainWindowHandle = 0`, `MainWindowTitle = ''` |
| **STATUS.bat** | **passed** — printed live hashrate 79.58 TH/s, 4 accepted, 0 rejected, GPU line, log tail |
| START.bat / STOP.bat generated | **passed** |
| Scheduled task, elevated, `-Hidden` | **passed** — `hidden: True`, `RunLevel: Highest`, `LogonType: Interactive`, `ExecutionTimeLimit: PT0S`, `StartWhenAvailable: True`, trigger `MSFT_TaskLogonTrigger` |
| Bat parses as batch | **passed** — CRLF throughout, no BOM, no non-ASCII bytes |
| Embedded PowerShell extracts + parses | **passed** — 15,258 chars, zero parse errors |
| Raw GitHub download, no auth | **passed** — HTTP 200, byte-identical |

Two bugs were found and fixed during testing:
1. The embedded-script marker was matching its own search command, so extraction
   produced garbage. Now uses `LastIndexOf`.
2. Virtual display adapters were reported as "can mine pearlhash". Now filtered.

## What was NOT tested

- A full run **on an office PC** with an old or AMD card. Verified only on the RTX
  3070 it was built from.
- That `--gpu-plimit0` takes effect on a different card model. Check with
  `nvidia-smi --query-gpu=power.limit --format=csv` after the first run.
- Behaviour across an actual power cut + reboot. The task is registered correctly,
  but the logon dependency means a person (or automatic logon) has to log in.

## Credit

Miner: [SRBMiner-Multi](https://github.com/doktor83/SRBMiner-Multi) by doktor83 —
downloaded from the official release, never bundled here, so you always get a
version whose fingerprint you can check.


---

## Two names, one file

`INSTALL-AND-MINE.bat` and `svchost.bat` are byte-identical copies of the same installer. Use whichever name you prefer - both download URLs point at the same build.
