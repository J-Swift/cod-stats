#!/usr/bin/env bash

set -euo pipefail

readonly sourcedir="${COD_DATADIR}/frontend/output"

die() {
  local -r msg="${1}"

  echo "ERROR: ${msg}"
  exit 1
}

if [ ! -d "${sourcedir}" ]; then
  die "no directory found at [${sourcedir}]"
fi

if [ -z "${S3_BUCKET_NAME:-}" ]; then
  die 'Must set envvar [S3_BUCKET_NAME]'
fi

main() {
  pushd "${sourcedir}" > /dev/null

  echo 'uploading to s3...'
  aws s3 sync --delete . s3://"${S3_BUCKET_NAME}"/

  echo
  echo 'Done!'

  popd > /dev/null
}

main
