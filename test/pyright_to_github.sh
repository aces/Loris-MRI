#!/bin/bash

# Script to convert Pyright JSON output to GitHub annotation format.
# Usage: pyright --outputjson | .pyright_to_github.sh

set -euo pipefail

# Read JSON input from standard input.
pyright_json=$(cat)

# Convert Pyright's JSON to GitHub annotations.
echo "$pyright_json" | jq -r '
.generalDiagnostics[]? |
"::\(.severity |
    if . == "error" then "error"
    elif . == "warning" then "warning"
    else "notice" end) file=\(.file),line=\(.range.start.line + 1),col=\(.range.start.character + 1),title=Pyright \(.rule // "diagnostic")::\(.message)"'

# Exit with Pyright's return code.
exit ${PIPESTATUS[0]}
