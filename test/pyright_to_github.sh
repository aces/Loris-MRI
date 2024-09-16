# This is a simple script to format Pyright errors (in JSON format) into GitHub errors, used by CI.
# TODO: Add formatting for warnings
jq -r '.generalDiagnostics[] | "::error file=\(.file),line=\(.range.start.line),col=\(.range.start.character)::\(.message)"'
