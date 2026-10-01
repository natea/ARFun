#!/bin/zsh
# Double-click to start the body tracker in Terminal (which has camera permission).
cd "$(dirname "$0")"
exec ~/.local/bin/uv run tracker.py --camera 0 --no-preview --fast "$@"
