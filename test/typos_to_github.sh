#!/bin/bash

# Script to convert Typos JSON output to GitHub annotation format.
# Usage: typos --format=json | ./typos_to_github.sh

set -euo pipefail

# Read JSON input from standard input.
typos_json=$(cat)

# Convert Typos JSON to GitHub annotations.
echo "$typos_json" | jq -s -r --arg root $(pwd) '
.[] |
    select(.type == "typo") |
    ($root + "/" + (.path | sub("^\\./"; ""))) as $fullpath |
    "::error file=\($fullpath),line=\(.line_num),col=\(.byte_offset),title=Typos::Found typo \(.typo) - suggestions: \(.corrections | join(", "))"'
