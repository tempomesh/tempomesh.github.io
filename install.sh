#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "8mem install failed: bash is required. Install bash, then rerun." >&2
  exit 1
fi

set -euo pipefail

APP_NAME="8mem"
WHEEL_URL="${EIGHTMEM_WHEEL_URL:-https://8mem.com/app/install/8mem-0.1.1-py3-none-any.whl}"
WHEEL_SHA256="${EIGHTMEM_WHEEL_SHA256:-feba0941aa78f9fcd0127a948d9feea5eca88a0d15901430ef927fe6ee83c2ca}"
RUNTIME_HOME="${EIGHTMEM_HOME:-$HOME/.8mem}"
VENV_DIR="${EIGHTMEM_VENV:-$HOME/.8mem/venv}"
BIN_DIR="${EIGHTMEM_BIN_DIR:-$HOME/.local/bin}"
RUN_SETUP="${EIGHTMEM_RUN_SETUP:-1}"
SETUP_MODE="skipped"
OPENCLAW_DETECTED="0"
OPENCLAW_WIRED="0"
OPENCLAW_WIRE_FAILED="0"
HERMES_DETECTED="0"
HERMES_WIRED="0"
HERMES_WIRE_FAILED="0"
TELEGRAM_CONFIGURED="0"
SERVER_STARTED="0"
SERVER_START_FAILED="0"

info() {
  printf '%s\n' "$*"
}

fail() {
  printf '8mem install failed: %s\n' "$*" >&2
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_supported_platform() {
  case "$(uname -s)" in
    Darwin|Linux)
      ;;
    *)
      fail "unsupported OS. Use macOS, Linux, or WSL2 for this installer."
      ;;
  esac
}

require_python() {
  has_command python3 || fail "python3 is required. Install Python 3.11+ and rerun this installer."
  python3 - <<'PY'
import sys
if sys.version_info < (3, 11):
    raise SystemExit("Python 3.11+ is required")
PY
}

require_tools() {
  has_command curl || fail "curl is required. Install curl, then rerun this installer."
}

check_optional_ollama() {
  if has_command ollama; then
    info "Ollama detected."
  else
    info "Ollama not detected. 8mem can install first, but local model replies need Ollama."
    info "Install later with:"
    info "  curl -fsSL https://ollama.com/install.sh | sh"
  fi
}

create_venv() {
  info "Creating local 8mem environment: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
}

download_wheel() {
  mkdir -p "$RUNTIME_HOME/tmp"
  WHEEL_PATH="$RUNTIME_HOME/tmp/$(basename "$WHEEL_URL")"
  info "Downloading 8mem package:"
  info "  $WHEEL_URL"
  curl -fsSL "$WHEEL_URL" -o "$WHEEL_PATH"
  python3 - "$WHEEL_PATH" "$WHEEL_SHA256" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected = sys.argv[2].lower()
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"SHA256 mismatch for {path.name}: expected {expected}, got {actual}")
PY
}

install_8mem() {
  info "Installing 8mem from verified package."
  "$VENV_DIR/bin/python" -m pip install --upgrade "$WHEEL_PATH"
}

install_command_shim() {
  mkdir -p "$BIN_DIR"
  ln -sf "$VENV_DIR/bin/8mem" "$BIN_DIR/8mem"
}

path_contains_bin_dir() {
  case ":$PATH:" in
    *":$BIN_DIR:"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_interactive_tty() {
  [ -r /dev/tty ] && [ -w /dev/tty ] && { : < /dev/tty; } 2>/dev/null
}

confirm_default_yes() {
  local prompt="$1"
  local answer

  printf '%s' "$prompt [Y/n] " > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "${answer:-}" in
    ""|y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

detect_agents() {
  if [ -f "$HOME/.openclaw/openclaw.json" ]; then
    OPENCLAW_DETECTED="1"
  fi
  if [ -f "$HOME/.hermes/config.yaml" ]; then
    HERMES_DETECTED="1"
  fi
}

wire_detected_agents() {
  detect_agents
  if [ "$OPENCLAW_DETECTED" = "0" ] && [ "$HERMES_DETECTED" = "0" ]; then
    info ""
    info "OpenClaw and Hermes not detected. 8mem will run as a standalone memory bot if Telegram was configured."
    return
  fi

  info ""
  if [ "$OPENCLAW_DETECTED" = "1" ] && [ "$HERMES_DETECTED" = "1" ]; then
    info "OpenClaw and Hermes detected."
  elif [ "$OPENCLAW_DETECTED" = "1" ]; then
    info "OpenClaw detected."
  else
    info "Hermes detected."
  fi

  if [ "$OPENCLAW_DETECTED" = "1" ] && confirm_default_yes "Wire 8mem into your OpenClaw agent now?"; then
    if "$VENV_DIR/bin/8mem" setup --mode openclaw --non-interactive --skip-telegram --skip-llm-check --no-status --no-next-steps; then
      OPENCLAW_WIRED="1"
    else
      OPENCLAW_WIRE_FAILED="1"
      info "OpenClaw wiring was skipped because setup could not safely update the workspace."
      info "Run this after fixing the OpenClaw workspace issue:"
      info "  8mem setup --mode openclaw"
    fi
  fi

  if [ "$HERMES_DETECTED" = "1" ] && confirm_default_yes "Wire 8mem into your Hermes agent now?"; then
    if "$VENV_DIR/bin/8mem" setup --mode hermes --non-interactive --skip-telegram --skip-llm-check --no-status --no-next-steps; then
      HERMES_WIRED="1"
    else
      HERMES_WIRE_FAILED="1"
      info "Hermes wiring was skipped because setup could not safely update Hermes."
      info "Run this after fixing the Hermes warning:"
      info "  8mem setup --mode hermes"
    fi
  fi
}

run_setup() {
  if [ "$RUN_SETUP" != "1" ]; then
    info "Skipping setup because EIGHTMEM_RUN_SETUP=$RUN_SETUP"
    SETUP_MODE="skipped"
    return
  fi

  info ""
  info "Running first-time setup."
  if has_interactive_tty; then
    SETUP_MODE="interactive"
    "$VENV_DIR/bin/8mem" setup --mode both --skip-llm-check --no-next-steps < /dev/tty
    wire_detected_agents
  else
    SETUP_MODE="non_interactive"
    info "No interactive terminal detected; running safe non-interactive setup."
    "$VENV_DIR/bin/8mem" setup --non-interactive --skip-telegram --skip-llm-check --no-next-steps
    detect_agents
  fi
  if [ -f "$RUNTIME_HOME/.env" ] && grep -q '^TELEGRAM_BOT_TOKEN=' "$RUNTIME_HOME/.env"; then
    TELEGRAM_CONFIGURED="1"
  fi
}

run_doctor() {
  info ""
  info "Running 8mem doctor."
  "$VENV_DIR/bin/8mem" doctor || true
}

start_server() {
  info ""
  info "Starting local 8mem server."
  if "$VENV_DIR/bin/8mem" start; then
    SERVER_STARTED="1"
  else
    SERVER_START_FAILED="1"
    info "8mem was installed, but the server did not start automatically."
    info "Run this after resolving the warning above:"
    info "  8mem start"
  fi
}

print_next_steps() {
  info ""
  info "8mem installed."
  info ""
  info "Command installed at:"
  info "  $VENV_DIR/bin/8mem"
  info ""
  info "If your shell can see $BIN_DIR, you can run:"
  info "  8mem doctor"
  info "  8mem start"
  info "  8mem status"
  info ""
  if ! path_contains_bin_dir; then
    info "Your current shell PATH does not include $BIN_DIR."
    info "For this terminal, run:"
    info "  export PATH=\"$BIN_DIR:\$PATH\""
    info ""
    info "Or use the direct commands below."
    info ""
  fi
  info "If not, run:"
  info "  $VENV_DIR/bin/8mem doctor"
  info "  $VENV_DIR/bin/8mem start"
  info "  $VENV_DIR/bin/8mem status"
  info ""
  info "Local API key lookup for /v1 APIs:"
  info "  grep '^EIGHTMEM_LOCAL_API_KEY=' $RUNTIME_HOME/.env"
  info ""
  info "Then open:"
  info "  http://127.0.0.1:8787"
  if [ "$SERVER_STARTED" = "1" ]; then
    info ""
    info "8mem server is already running in the background."
  elif [ "$SERVER_START_FAILED" = "1" ]; then
    info ""
    info "8mem server is not running yet because automatic start failed."
    info "After fixing the warning above, run:"
    info "  8mem start"
  fi
  info ""
  info "If Ollama is not installed yet:"
  info "  curl -fsSL https://ollama.com/install.sh | sh"
  info "  ollama pull qwen2.5:14b"
  info ""
  if [ "$TELEGRAM_CONFIGURED" != "1" ]; then
    info "For Telegram, rerun setup when you have your BotFather token:"
    info "  8mem setup --mode telegram"
  fi
  if [ "$OPENCLAW_WIRED" = "1" ]; then
    info ""
    info "OpenClaw is wired."
    info "Test in your OpenClaw agent:"
    info "  /passport"
    info "  /compare coffee"
    info "  remember I prefer bullet points"
    info ""
    info "To undo OpenClaw wiring:"
    info "  8mem uninstall --mode openclaw"
  elif [ "$OPENCLAW_WIRE_FAILED" = "1" ]; then
    info ""
    info "OpenClaw was detected, but the OpenClaw agent was not wired."
    info "Fix the workspace warning above, then run:"
    info "  8mem setup --mode openclaw"
  elif [ "$OPENCLAW_DETECTED" = "1" ] || { [ "$SETUP_MODE" != "interactive" ] && [ -f "$HOME/.openclaw/openclaw.json" ]; }; then
    info ""
    info "OpenClaw detected. Wire your OpenClaw agent with:"
    info "  8mem setup --mode openclaw"
  fi
  if [ "$HERMES_WIRED" = "1" ]; then
    info ""
    info "Hermes is wired."
    info "Test in your Hermes agent:"
    info "  /refresh8mem"
    info "  /passport"
    info "  /corrections"
    info "  /compare coffee"
  elif [ "$HERMES_WIRE_FAILED" = "1" ]; then
    info ""
    info "Hermes was detected, but the Hermes agent was not wired."
    info "Fix the warning above, then run:"
    info "  8mem setup --mode hermes"
  elif [ "$HERMES_DETECTED" = "1" ] || { [ "$SETUP_MODE" != "interactive" ] && [ -f "$HOME/.hermes/config.yaml" ]; }; then
    info ""
    info "Hermes detected. Wire your Hermes agent with:"
    info "  8mem setup --mode hermes"
  fi
  if [ "$OPENCLAW_DETECTED" = "0" ] && [ "$HERMES_DETECTED" = "0" ]; then
    info ""
    if [ "$TELEGRAM_CONFIGURED" = "1" ]; then
      info "Your standalone memory bot is configured."
      info "After starting 8mem, test in Telegram:"
      info "  /passport"
      info "  /compare productivity"
      info "  remember I prefer short answers"
    else
      info "OpenClaw and Hermes not detected. 8mem is installed as a local memory server."
    fi
  fi
}

main() {
  info "Installing 8mem public beta"
  require_supported_platform
  require_python
  require_tools
  check_optional_ollama
  create_venv
  download_wheel
  install_8mem
  install_command_shim
  run_setup
  start_server
  run_doctor
  print_next_steps
}

main "$@"
