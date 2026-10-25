#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
"build/Cyan Codex Usage.app/Contents/MacOS/Cyan Codex Usage" --self-test
codesign --verify --deep --strict "build/Cyan Codex Usage.app"
