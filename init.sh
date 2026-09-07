#!/usr/bin/env bash
# Week 8 tool check. Works on Ubuntu and macOS.

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT" || exit 1

echo "=============================================="
echo "  w08_fastapi_app — Initialize"
echo "=============================================="

missing=0

if command -v git >/dev/null 2>&1; then
  echo "✅ git: $(git --version)"
else
  echo "❌ git missing — install Git, then rerun bash init.sh"
  missing=$((missing + 1))
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "📦 uv missing — installing from astral.sh..."
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # This PATH only applies to init.sh itself -- a child process cannot change
    # the parent shell's PATH, so the student's terminal still has no uv.
    PATH="$HOME/.local/bin:$PATH"
    uv_just_installed=true
  fi
fi

if command -v uv >/dev/null 2>&1; then
  echo "✅ uv: $(uv --version)"
else
  echo "❌ uv missing — run: curl -LsSf https://astral.sh/uv/install.sh | sh"
  missing=$((missing + 1))
fi

if command -v node >/dev/null 2>&1; then
  node_version=$(node --version)
  node_clean=${node_version#v}
  node_major=${node_clean%%.*}
  node_rest=${node_clean#*.}
  node_minor=${node_rest%%.*}
  if [ "$node_major" -gt 20 ] || { [ "$node_major" -eq 20 ] && [ "$node_minor" -ge 19 ]; }; then
    echo "✅ node: $node_version"
  else
    echo "❌ node $node_version is too old — install Node 22, then rerun bash init.sh"
    missing=$((missing + 1))
  fi
else
  echo "❌ node missing — install Node 22, then rerun bash init.sh"
  missing=$((missing + 1))
fi

if command -v npm >/dev/null 2>&1; then
  echo "✅ npm: $(npm --version)"
else
  echo "❌ npm missing — install Node 22, then rerun bash init.sh"
  missing=$((missing + 1))
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "✅ docker: $(docker --version)"
  echo "✅ compose: $(docker compose version)"
else
  echo "❌ Docker or the compose plugin is missing (or the engine is not running)."
  echo "   No GUI needed. Install it from the course environment guide:"
  echo "     Ubuntu: https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#25-install-docker"
  echo "             then: sudo usermod -aG docker \$USER   (log out and back in)"
  echo "     macOS:  brew install --cask orbstack"
  echo "   Check with: docker run --rm hello-world   (must work WITHOUT sudo)"
  missing=$((missing + 1))
fi

echo ""
if [ "$missing" -eq 0 ]; then
  if [ "${uv_just_installed:-false}" = true ]; then
    echo "✅ Tools ready — but uv was just installed."
    echo "   This terminal cannot see it yet. CLOSE it and open a new one"
    echo "   (or run: source \"$HOME/.local/bin/env\"), check with: uv --version"
    echo "   Then open README.md and begin Section 1."
  else
    echo "✅ Tools ready. Open README.md and begin Section 1."
  fi
  exit 0
fi

echo "❌ $missing tool check(s) failed. Fix them before Section 1."
exit 1
