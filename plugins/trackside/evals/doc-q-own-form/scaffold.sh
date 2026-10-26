#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/../_fixture/sandbox.sh"
bash "$(dirname "$0")/../_fixture/rfc.sh"
