# Toolchain setup

Everything in SimStack runs in emulation. No physical board, debugger or programmer is
required — only free, open-source software.

## Pinned versions

| Component | Version | Why pinned |
|---|---|---|
| Zephyr RTOS | `v4.4.2` | Latest stable at time of writing; `stm32f4_disco` is an upstream-supported board target |
| Zephyr SDK | `1.0.1` | Provides the `arm-zephyr-eabi` cross-toolchain |
| Renode | `1.17.0` | Ships STM32F4 Discovery platform definitions out of the box |
| Buildroot | set in Milestone 3 | Pinned when that milestone lands |

Versions were verified against upstream release feeds on 2026-09-18. They are pinned
deliberately so that CI and a local checkout build the same thing; bump them as a
standalone commit so a regression is easy to bisect.

## Quick start

```bash
./scripts/bootstrap.sh
```

This runs four stages, each of which can also be run on its own
(`./scripts/bootstrap.sh zephyr`):

1. **`system`** — `apt` packages: Zephyr's documented Ubuntu dependency list, plus
   `qemu-system-arm` and the Buildroot host requirements. **Requires `sudo`** and will
   prompt for your password.
2. **`zephyr`** — creates a Python venv at `~/zephyrproject/.venv`, installs `west`,
   initialises the workspace at the pinned Zephyr tag, and installs the Zephyr SDK.
   Only the `arm-zephyr-eabi` toolchain is fetched (a few hundred MB rather than the
   multi-GB full SDK).
3. **`renode`** — downloads the portable Renode tarball into `~/.local/opt/` and symlinks
   `renode` / `renode-test` into `~/.local/bin`. No `sudo`, nothing installed system-wide.
4. **`verify`** — checks every tool resolves and reports versions.

The script is idempotent; re-running it is cheap and safe.

## Workspace layout

The Zephyr workspace lives **outside** this repository, at `~/zephyrproject`:

```
~/zephyrproject/          # west workspace — fetched, not vendored
├── .venv/                #   Python environment (west, pyelftools, ...)
├── zephyr/               #   Zephyr RTOS sources at v4.4.2
└── modules/              #   HAL and third-party modules

~/Projects/simstack/      # this repository — application code only
└── zephyr-app/           #   built with: west build -b stm32f4_disco zephyr-app
```

Keeping the workspace out of the repo means the repository stays small and contains only
code that was actually written for this project, rather than several gigabytes of vendored
upstream sources. Zephyr fully supports building an application from outside the workspace,
which is how the build commands below work.

## Daily use

Activate the toolchain in any new shell:

```bash
source ~/zephyrproject/.venv/bin/activate
```

Then, from the repository root:

```bash
west build -b stm32f4_disco zephyr-app
```

Add `-p always` to force a clean (pristine) build when changing board or configuration.

## Notes and gotchas

- **`~/.local/bin` on `PATH`.** The bootstrap warns if it is missing. Add
  `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` if so.
- **CMake version.** Zephyr 4.4 requires CMake ≥ 3.28. Ubuntu 26.04 ships a new enough
  version; on older Ubuntu releases the distro CMake is too old and must come from Kitware's
  APT repository instead.
- **WSL2.** Everything here is headless and runs fine under WSL2. Renode's interactive GUI
  monitor needs an X server, but the `--console` and `--disable-xwt` headless modes used by
  the tests and CI do not.
- **Disk.** Budget roughly 10 GB: Zephyr sources and modules ~2 GB, SDK ARM toolchain
  ~1 GB, Renode ~0.5 GB, and Buildroot in Milestone 3 ~5 GB of build output.
