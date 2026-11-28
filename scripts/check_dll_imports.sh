#!/usr/bin/env bash
# scripts/check_dll_imports.sh -- every DLL a Windows binary of the release imports is one Windows ships.
#
#   bash scripts/check_dll_imports.sh <file.dll|file.exe>...
#
# Allowed: KERNEL32.dll and the Universal CRT's API sets (api-ms-win-crt-*.dll), which every Windows 10+ has in-box.
# Anything else -- VCRUNTIME140.dll from the VC++ redistributable, libgcc_s or libwinpthread from MSYS2 -- is missing
# on a machine without that package, and the engine would start without its grammars. Each file's imports are
# printed; exit 1 names every file with an import outside the list, 2 for no file or a file objdump cannot read.
#
# OBJDUMP overrides the objdump to run (the release job uses the UCRT64 one; TESTS/release_script_spec.lua a fake).
set -euo pipefail

objdump_bin="${OBJDUMP:-objdump}"

if [ "$#" -eq 0 ]; then
  echo "usage: bash scripts/check_dll_imports.sh <file>..." >&2
  exit 2
fi

bad=0
for file in "$@"; do
  if ! dump="$("$objdump_bin" -p "$file" 2>&1)"; then
    echo "check_dll_imports: cannot read $file: $dump" >&2
    exit 2
  fi
  imports="$(printf '%s\n' "$dump" | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p' | tr -d '\r')"
  echo "$file: $(printf '%s' "$imports" | tr '\n' ' ')"
  while IFS= read -r dll; do
    [ -z "$dll" ] && continue
    lower="$(printf '%s' "$dll" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      kernel32.dll | api-ms-win-crt-*.dll) ;;
      *)
        echo "check_dll_imports: $file imports $dll, which Windows does not ship" >&2
        bad=1
        ;;
    esac
  done <<<"$imports"
done
exit "$bad"
