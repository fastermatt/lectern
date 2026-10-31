#!/bin/bash
# Throughline is now Thruline Bible. This path is kept so older install links keep working.
set -euo pipefail
exec bash <(curl -fsSL --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/fastermatt/thruline-bible/main/scripts/install-thruline.sh) "$@"
