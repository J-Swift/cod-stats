#!/usr/bin/env bash

set -euo pipefail

print_header() {
  local -r msg="${1}"
  local -r print_leading_space="${2:-true}"
  if $print_leading_space; then
    echo
  fi
  echo '--------------------------------------------------------------------------------'
  echo "> ${msg} <"
  echo '--------------------------------------------------------------------------------'
}

get_ts() {
  echo $( date +%s%N | cut -b1-13 )
}

main() {
  local -r start=$( get_ts )

  print_header 'Pulling latest matches' false
  pushd fetcher > /dev/null
  node fetch_matches.js
  popd > /dev/null

  print_header 'Updating database'
  pushd parser > /dev/null
  ./parse_matches.sh
  popd > /dev/null

  print_header 'Regenerating FE and deploying'
  pushd frontend > /dev/null
  ./generate_lookup_data.sh && ./deploy.sh
  popd > /dev/null

  local -r end=$( get_ts )

  print_header "Success! Ran in [$(((end-start)/1000))] seconds"
}

main
