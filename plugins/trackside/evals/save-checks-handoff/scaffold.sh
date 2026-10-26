#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/../_fixture/sandbox.sh"
# The state uses a term nothing in the track defines; the user explains it only in passing.
cat > api/app.js <<'EOJ'
function applyDiscount(total, code) {
  if (code === "TEN") return total * 0.9;
  return total;
}
module.exports = { applyDiscount };
EOJ
awk '{ sub(/^- Ticket: none \[verified\]$/, "- T-1: the BX path is half wired [assumed]"); print }
     /^## Next step/ { print "- finish the BX path" }' .trackside/demo/tickets/STATE.md > .trackside/demo/tickets/STATE.tmp
mv .trackside/demo/tickets/STATE.tmp .trackside/demo/tickets/STATE.md
git -C .trackside commit -qam "T-1 in progress"
