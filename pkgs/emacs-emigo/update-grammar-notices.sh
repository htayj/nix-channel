#!/usr/bin/env bash
# Regenerate grammar-notices.json from the grammar pins of the packaged
# tree-sitter-language-pack release.
#
#   update-grammar-notices.sh LANGUAGE_DEFINITIONS_JSON [CACHE_DIR]
#
# LANGUAGE_DEFINITIONS_JSON is sources/language_definitions.json of the
# tree-sitter-language-pack source at the version in the pinned Nixpkgs.
# For every grammar the manifest records, at the pinned revision:
#
#   licence         licence, copying and notice files of the repository root
#                   and of the grammar directory
#   manifest        package manifests declaring the licence, for grammars
#                   that ship no licence file
#   other-revision-licence
#                   a licence file from another revision of the repository,
#                   for the grammars in the table below
#   source-notice   hand-written sources compiled into the parser that carry
#                   their own copyright notice
#
# Review the resulting diff: the file names select evidence, they do not
# classify it.  Needs curl, git and jq.
set -euo pipefail

definitions=${1:?usage: update-grammar-notices.sh LANGUAGE_DEFINITIONS_JSON [CACHE_DIR]}
cache=${2:-$(mktemp -d)}
output=$(dirname "$(readlink -f "$0")")/grammar-notices.json
mkdir -p "$cache/trees" "$cache/files"

# Grammars whose pinned revision holds no licence file while another
# revision of the same repository does.  Value: that revision and the file.
declare -A elsewhere=(
  # Pinned to a gh-pages commit holding only README.md and src/, which
  # .github/workflows/publishsource.yml deployed from this master commit.
  [groovy]="961de185860db4e523fd47fe26d7b16d0c44f9e5 LICENSE"
  # The commit that added the licence file, a descendant of the pinned one.
  [tmux]="8eb50b418286d68344d2b5cb42ac11adda877ecc LICENSE"
)

# Print the file list of REPOSITORY at REVISION, cached under NAME.
tree() {
  local name=$1 repository=$2 revision=$3 list=$cache/trees/$1.txt scratch
  if [ ! -s "$list" ]; then
    scratch=$(mktemp -d)
    git init -q --bare "$scratch"
    GIT_TERMINAL_PROMPT=0 git -C "$scratch" fetch -q --depth 1 \
      --filter=blob:none "$repository" "$revision"
    git -C "$scratch" ls-tree -r --name-only FETCH_HEAD > "$list"
    rm -rf "$scratch"
  fi
  echo "$list"
}

# Download PATH of REPOSITORY at REVISION and print the cached file name.
fetch() {
  local name=$1 repository=$2 revision=$3 path=$4
  local file=$cache/files/$name/${path//\//%}
  mkdir -p "$cache/files/$name"
  [ -s "$file" ] || curl -fsSL --retry 3 -m 60 -o "$file" \
    "${repository/https:\/\/github.com\//https://raw.githubusercontent.com/}/$revision/$path"
  echo "$file"
}

entry() {
  jq -n --arg path "$1" --arg kind "$2" --arg rev "$3" \
    --arg sha256 "$(sha256sum "$4" | cut -d' ' -f1)" \
    '{path: $path, kind: $kind, rev: $rev, sha256: $sha256}'
}

files() {
  local name=$1 repository=$2 revision=$3 directory=$4
  local prefix=${directory:+$directory/} list licences path file manifest other
  list=$(tree "$name" "$repository" "$revision")

  licences=$({
    grep -iE '^[^/]*(licen[sc]e|copying|notice|unlicense|copyright|patents|authors)[^/]*$' "$list" || true
    [ -z "$directory" ] ||
      grep -iE "^$directory/[^/]*(licen[sc]e|copying|notice|unlicense|copyright)[^/]*\$" "$list" || true
  } | { grep -v '\.toml$' || true; } | sort -u)

  if [ -n "$licences" ]; then
    while read -r path; do
      entry "$path" licence "$revision" "$(fetch "$name" "$repository" "$revision" "$path")"
    done <<< "$licences"
  else
    if [ -n "${elsewhere[$name]:-}" ]; then
      read -r other path <<< "${elsewhere[$name]}"
      entry "$path" other-revision-licence "$other" \
        "$(fetch "$name" "$repository" "$other" "$path")"
    fi
    for manifest in Cargo.toml package.json pyproject.toml tree-sitter.json; do
      path=$prefix$manifest
      grep -qxF "$path" "$list" || continue
      file=$(fetch "$name" "$repository" "$revision" "$path")
      if grep -qiE '"?license(\.text)?"? *[:=]' "$file"; then
        entry "$path" manifest "$revision" "$file"
      fi
    done
  fi

  {
    grep -E "^${prefix}src/.*\.(c|cc|cpp|h|hpp|hh)\$" "$list" |
      grep -vE '/parser\.c$|/tree_sitter/' || true
    # Scanners of multi-grammar repositories include shared sources.
    [ -z "$directory" ] || grep -E '^common/.*\.(c|cc|h)$' "$list" || true
  } | while read -r path; do
    file=$(fetch "$name" "$repository" "$revision" "$path")
    if grep -qiE 'copyright|SPDX-License|licensed under' "$file"; then
      entry "$path" source-notice "$revision" "$file"
    fi
  done
}

jq -r 'to_entries[] | [.key, .value.repo, .value.rev, (.value.directory // "")] | @tsv' \
  "$definitions" |
  while IFS=$'\t' read -r name repository revision directory; do
    files "$name" "$repository" "$revision" "$directory" |
      jq -s --arg name "$name" --arg repo "$repository" --arg rev "$revision" \
        '{name: $name, repo: $repo, rev: $rev, files: .}'
  done | jq -s . > "$output.new"

if missing=$(jq -er '[.[] | select(.files | map(.kind != "source-notice") | any | not) | .name] | select(length > 0) | join(" ")' "$output.new"); then
  echo "no licence evidence for: $missing" >&2
  exit 1
fi
mv "$output.new" "$output"
