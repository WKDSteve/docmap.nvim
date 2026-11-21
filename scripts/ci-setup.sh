#!/usr/bin/env bash
#
# Prepares a hosted CI leg for the pipeline (`ci.workflow.setup` of .testing.lua runs it before `scripts/ci.sh`):
#
#   scripts/ci-setup.sh parsers   every hosted leg: builds the tree-sitter grammars the call specs need into
#                                 .deps/ts-parsers and names the directory in $GITHUB_ENV (DOCMAP_TS_PARSERS_DIR,
#                                 which TESTS/minimal_init.lua appends to the runtimepath)
#   scripts/ci-setup.sh linux     the ubuntu leg with the whole profile: PUC Lua 5.4 with lfs and dkjson for the step
#                                 `standalone`, and ../lib.nvim beside the checkout for the step `map`
#
# Nothing here runs on a developer's machine: a local run finds its own parsers, Lua and sibling checkouts.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# The grammars, pinned by commit (third-party code that is compiled and loaded by the specs). All of them ship a
# generated parser.c, so `tree-sitter build` (compile) is enough, never `tree-sitter generate`. Bump on purpose.
#   javascript, typescript (+tsx): the ECMAScript backend; go: go_calls_spec.lua, the only gate on the package-scope
#   resolver; python: python_calls_spec.lua (methods_need_receiver, imports); rust: rust_calls_spec.lua (`::` paths).
GRAMMARS=(
  "javascript 58404d8cf191d69f2674a8fd507bd5776f46cb11"
  "typescript 75b3874edb2dc714fb1fd77a32013d0f8699989f"
  "go 2346a3ab1bb3857b48b29d779a1ef9799a248cd7"
  "python 26855eabccb19c6abf499fbc5b8dc7cc9ab8bc64"
  "rust 77a3747266f4d621d0757825e6b11edcbf991ca5"
)

# fetch <repo> <commit> <dir>: exactly that commit, nothing else of the history.
fetch() {
  git init -q "$3"
  git -C "$3" fetch -q --depth 1 "https://github.com/tree-sitter/$1.git" "$2"
  git -C "$3" checkout -q FETCH_HEAD
}

parsers() {
  command -v tree-sitter >/dev/null 2>&1 || {
    echo "ci-setup: tree-sitter is not on PATH (ci.workflow.packages installs tree-sitter-cli)" >&2
    exit 1
  }
  local src="${RUNNER_TEMP:-$ROOT/.deps}/grammars"
  local out="$ROOT/.deps/ts-parsers/parser"
  mkdir -p "$src" "$out"
  local entry name sha
  for entry in "${GRAMMARS[@]}"; do
    name="${entry% *}"
    sha="${entry#* }"
    fetch "tree-sitter-$name" "$sha" "$src/$name"
    if [[ "$name" == "typescript" ]]; then
      tree-sitter build --output "$out/typescript.so" "$src/typescript/typescript"
      tree-sitter build --output "$out/tsx.so" "$src/typescript/tsx"
    else
      tree-sitter build --output "$out/$name.so" "$src/$name"
    fi
  done
  echo "DOCMAP_TS_PARSERS_DIR=$ROOT/.deps/ts-parsers" >>"${GITHUB_ENV:-/dev/null}"
  ls -l "$out"
}

linux() {
  # The standalone build under a PUC Lua, not LuaJIT (scripts/ci.lua looks for lua5.4 first).
  sudo apt-get update -q
  sudo apt-get install -y lua5.4 liblua5.4-dev luarocks
  sudo luarocks --lua-version=5.4 install luafilesystem
  sudo luarocks --lua-version=5.4 install dkjson
  lua5.4 -e "require('lfs') require('dkjson') print('lua5.4 with lfs and dkjson')"
  # `.docmap.json` resolves lib.nvim at ../lib.nvim; without it the map is generated with other external links and
  # the step `map` calls the committed one stale. A symlink to the checkout below .deps/, not a second clone.
  if [[ ! -e ../lib.nvim ]]; then
    ln -s "$ROOT/.deps/lib.nvim" ../lib.nvim
  fi
}

case "${1:-}" in
  parsers) parsers ;;
  linux) linux ;;
  *)
    echo "usage: scripts/ci-setup.sh parsers|linux" >&2
    exit 2
    ;;
esac
