#!/usr/bin/env bash
#
# SimStack toolchain bootstrap.
#
# Installs everything needed to build and emulate both halves of the project:
#   - Zephyr RTOS workspace + SDK (ARM cross-toolchain)  -> Milestones 1, 2
#   - Renode                                             -> Milestones 1, 2
#   - QEMU + Buildroot host dependencies                 -> Milestone 3
#
# Safe to re-run: every step checks for existing state before doing work.
#
# Usage:
#   ./scripts/bootstrap.sh            # everything
#   ./scripts/bootstrap.sh zephyr     # one component: system|zephyr|renode|verify
#
set -euo pipefail

# --- Pinned versions -------------------------------------------------------
# Verified against upstream releases on 2026-09-18. Bump deliberately.
ZEPHYR_VERSION="v4.4.2"
RENODE_VERSION="1.17.0"

# --- Paths -----------------------------------------------------------------
ZEPHYR_WS="${ZEPHYR_WS:-$HOME/zephyrproject}"
OPT_DIR="${OPT_DIR:-$HOME/.local/opt}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
RENODE_DIR="$OPT_DIR/renode-$RENODE_VERSION"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[0;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[0;33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[0;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. System packages (requires sudo — you will be prompted for your password)
# ---------------------------------------------------------------------------
install_system() {
  log "Installing system packages (sudo required)"

  # Zephyr's documented Ubuntu dependency list, plus QEMU and the Buildroot
  # host requirements for Milestone 3.
  sudo apt-get update
  sudo apt-get install --no-install-recommends -y \
    git cmake ninja-build gperf ccache dfu-util device-tree-compiler wget \
    python3-dev python3-venv python3-pip python3-tk xz-utils file make \
    gcc gcc-multilib g++-multilib libsdl2-dev libmagic1 \
    qemu-system-arm \
    bc bzip2 cpio rsync unzip libncurses-dev flex bison libssl-dev \
    curl ca-certificates

  # Renode's portable build still needs the Mono/.NET runtime libraries for
  # its GUI bits; the headless path we use in CI does not, but installing
  # these keeps the interactive monitor usable.
  sudo apt-get install --no-install-recommends -y \
    libc6-dev libgtk2.0-0 || warn "optional Renode GUI deps unavailable (headless still works)"

  ok "System packages installed"

  local cmake_ver
  cmake_ver="$(cmake --version | head -1 | awk '{print $3}')"
  ok "cmake $cmake_ver (Zephyr requires >= 3.28.0)"
}

# ---------------------------------------------------------------------------
# 2. Zephyr workspace + SDK
# ---------------------------------------------------------------------------
install_zephyr() {
  log "Setting up Zephyr workspace at $ZEPHYR_WS ($ZEPHYR_VERSION)"

  command -v cmake >/dev/null || die "cmake not found — run './scripts/bootstrap.sh system' first"

  if [[ ! -d "$ZEPHYR_WS/.venv" ]]; then
    python3 -m venv "$ZEPHYR_WS/.venv"
    ok "Created Python venv"
  else
    ok "Python venv already exists"
  fi

  # shellcheck disable=SC1091
  source "$ZEPHYR_WS/.venv/bin/activate"

  python -m pip install --quiet --upgrade pip
  python -m pip install --quiet west
  ok "west $(west --version | awk '{print $3}') installed"

  if [[ ! -d "$ZEPHYR_WS/.west" ]]; then
    west init --mr "$ZEPHYR_VERSION" \
      -m https://github.com/zephyrproject-rtos/zephyr "$ZEPHYR_WS"
    ok "Initialised west workspace"
  else
    ok "west workspace already initialised"
  fi

  cd "$ZEPHYR_WS"
  west update
  west zephyr-export
  west packages pip --install
  ok "Zephyr sources and Python dependencies up to date"

  log "Installing Zephyr SDK (ARM toolchain only — keeps the download small)"
  cd "$ZEPHYR_WS/zephyr"
  if west sdk list 2>/dev/null | grep -q 'arm-zephyr-eabi'; then
    ok "Zephyr SDK with arm-zephyr-eabi already installed"
  else
    # -t limits the install to the one target architecture we need
    # (the full SDK is many GB; this is a few hundred MB).
    west sdk install -t arm-zephyr-eabi
    ok "Zephyr SDK installed"
  fi
}

# ---------------------------------------------------------------------------
# 3. Renode (portable tarball — no sudo, no system-wide install)
# ---------------------------------------------------------------------------
install_renode() {
  log "Installing Renode $RENODE_VERSION"

  if [[ -x "$RENODE_DIR/renode" ]]; then
    ok "Renode $RENODE_VERSION already present at $RENODE_DIR"
  else
    mkdir -p "$OPT_DIR" "$BIN_DIR"
    local tarball="renode-${RENODE_VERSION}.linux-portable.tar.gz"
    local url="https://github.com/renode/renode/releases/download/v${RENODE_VERSION}/${tarball}"
    local tmp
    tmp="$(mktemp -d)"

    echo "    Downloading $tarball ..."
    if ! curl -fL --progress-bar -o "$tmp/$tarball" "$url"; then
      rm -rf "$tmp"
      die "Failed to download Renode from $url"
    fi

    mkdir -p "$RENODE_DIR"
    if ! tar -xzf "$tmp/$tarball" -C "$RENODE_DIR" --strip-components=1; then
      rm -rf "$tmp" "$RENODE_DIR"
      die "Failed to extract $tarball"
    fi
    # Cleaned up explicitly rather than via a RETURN trap: the trap fires after
    # bash has torn down the function's locals, so $tmp is unbound by then and
    # `set -u` aborts the cleanup, leaking the download into /tmp.
    rm -rf "$tmp"
    ok "Extracted to $RENODE_DIR"
  fi

  mkdir -p "$BIN_DIR"
  ln -sf "$RENODE_DIR/renode" "$BIN_DIR/renode"
  ln -sf "$RENODE_DIR/renode-test" "$BIN_DIR/renode-test"
  ok "Linked renode and renode-test into $BIN_DIR"

  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not on your PATH. Add this to your ~/.bashrc:"
    printf '\n        export PATH="%s:$PATH"\n\n' "$BIN_DIR"
  fi
}

# ---------------------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------------------
verify() {
  log "Verifying toolchain"
  local failed=0

  check() {
    local name="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
      ok "$name — $(eval "$cmd" 2>&1 | head -1)"
    else
      warn "$name — NOT FOUND"
      failed=1
    fi
  }

  check "cmake"          "cmake --version"
  check "ninja"          "ninja --version"
  check "dtc"            "dtc --version"
  check "qemu-system-arm" "qemu-system-arm --version"
  check "renode"         "$BIN_DIR/renode --version"

  if [[ -f "$ZEPHYR_WS/.venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$ZEPHYR_WS/.venv/bin/activate"
    check "west" "west --version"
    if [[ -d "$ZEPHYR_WS/zephyr" ]]; then
      ok "Zephyr sources — $(git -C "$ZEPHYR_WS/zephyr" describe --tags 2>/dev/null || echo present)"
    else
      warn "Zephyr sources — NOT FOUND"; failed=1
    fi

    # Ask west what it actually sees rather than trusting that the SDK
    # directory exists. An interrupted `west sdk install` leaves behind a
    # complete-looking tree of zero-byte files that a presence check happily
    # accepts but that cannot compile anything.
    local sdk_list
    sdk_list="$(cd "$ZEPHYR_WS/zephyr" && west sdk list 2>/dev/null || true)"
    if grep -q 'arm-zephyr-eabi' <<<"$sdk_list"; then
      ok "Zephyr SDK $(head -1 <<<"$sdk_list" | tr -d ':') with arm-zephyr-eabi"
    else
      warn "Zephyr SDK — missing or incomplete (run: west sdk install -t arm-zephyr-eabi)"
      failed=1
    fi
  else
    warn "Zephyr venv — NOT FOUND"; failed=1
  fi

  echo
  if [[ $failed -eq 0 ]]; then
    printf '\033[0;32mToolchain ready.\033[0m Activate it in any new shell with:\n\n'
    printf '    source %s/.venv/bin/activate\n\n' "$ZEPHYR_WS"
  else
    die "Some components are missing — re-run ./scripts/bootstrap.sh"
  fi
}

# ---------------------------------------------------------------------------
main() {
  case "${1:-all}" in
    system) install_system ;;
    zephyr) install_zephyr ;;
    renode) install_renode ;;
    verify) verify ;;
    all)
      install_system
      install_zephyr
      install_renode
      verify
      ;;
    *) die "Unknown component '$1' (expected: system|zephyr|renode|verify|all)" ;;
  esac
}

main "$@"
