# SimStack

A heterogeneous embedded system built and tested entirely in emulation — no physical hardware.

A Zephyr RTOS firmware image runs on an emulated STM32F4 Discovery board under
[Renode](https://renode.io/), alongside a custom Buildroot Linux image running under QEMU.
Both sides are exercised by an automated test suite in CI, including HIL-style tests that boot
the real firmware binary in the emulator and assert on observable hardware behaviour.

> **Status:** active development. This repository is built milestone by milestone, and each
> milestone is verified end-to-end before the next one starts. See the milestone table below
> for what is actually working today — nothing is listed as done until it runs.

## Architecture

```
┌─────────────────────────────────┐        ┌──────────────────────────────────┐
│   MCU side (Milestone 1)        │        │   Host side (Milestone 3)        │
│   STM32F407 @ Renode            │        │   ARM Linux @ QEMU               │
│                                 │        │                                  │
│   Zephyr RTOS                   │        │   Buildroot rootfs + kernel      │
│   ┌───────────────────────┐     │        │   ┌────────────────────────┐     │
│   │ sensor thread         │     │        │   │ user space             │     │
│   │   │ k_msgq             │     │        │   │   │ read()             │     │
│   │   ▼                    │     │  UART  │   │   ▼                    │     │
│   │ processing thread     │◄───┼────────┼──►│ /dev/simstack          │     │
│   │   │ k_sem              │     │  (SPI) │   │   │                    │     │
│   │   ▼                    │     │        │   │   ▼                    │     │
│   │ output thread → LED   │     │        │   │ char device driver     │     │
│   └───────────────────────┘     │        │   └────────────────────────┘     │
│   custom Zephyr GPIO driver     │        │   loadable kernel module         │
└─────────────────────────────────┘        └──────────────────────────────────┘
             ▲                                            ▲
             │                                            │
      ┌──────┴────────────────────────────────────────────┴──────┐
      │  CI (Milestone 2): build → ztest → Renode/Robot HIL tests │
      └───────────────────────────────────────────────────────────┘
```

The two halves model how a real sensor-hub product is architected: a low-power MCU running
an RTOS handles deterministic, hard-real-time sampling and actuation, while a Linux host
handles storage, connectivity and application logic, with the two talking over a serial link.
Milestone 4 adds the schematic for the carrier board that would host the MCU side in silicon.

## Milestones

| # | Milestone | Status |
|---|---|---|
| 0 | Repository, toolchain bootstrap, CI skeleton | 🚧 in progress |
| 1 | Zephyr RTOS app on Renode-emulated STM32F4 (threads, msgq, semaphore, custom driver) | ⬜ not started |
| 2 | `ztest` unit tests + Renode/Robot HIL tests + GitHub Actions CI | ⬜ not started |
| 3 | Buildroot Linux image under QEMU + custom character device driver | ⬜ not started |
| 4 | KiCad carrier-board schematic with design rationale | ⬜ not started |
| 5 | Documentation and portfolio write-up | ⬜ not started |

## Repository layout

```
simstack/
├── zephyr-app/           # Milestone 1: Zephyr application + custom driver
│   └── boards/renode/    #   Renode .resc launch scripts
├── tests/
│   ├── ztest/            # Milestone 2: unit tests (native_sim target)
│   └── robot/            # Milestone 2: Renode HIL-style tests
├── linux-image/          # Milestone 3: Buildroot config + kernel module
├── hardware/             # Milestone 4: KiCad project
├── scripts/              # Toolchain bootstrap and helper scripts
├── docs/                 # Per-milestone notes and debugging write-ups
└── .github/workflows/    # Milestone 2: CI pipeline
```

## Getting started

Everything runs in emulation, so no hardware is required. See
[docs/toolchain.md](docs/toolchain.md) for the full toolchain setup.

```bash
./scripts/bootstrap.sh
```

## Why this project

Emulation-first development is how embedded teams get CI that actually means something:
the same firmware binary that would ship to silicon is booted in Renode on every push, and
tests assert on GPIO state and UART output rather than on mocked-out abstractions. This
repository is a working demonstration of that workflow across both an RTOS target and an
embedded Linux target.

## License

MIT — see [LICENSE](LICENSE).
