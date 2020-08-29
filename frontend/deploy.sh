#!/usr/bin/env sh

set -eu

if [ -z "${S3_BUCKET_NAME:-}" ]; then
  echo 'Must set envvar [S3_BUCKET_NAME]'
  exit 1
fi

main() {
  echo 'uploading to s3...'
  aws s3 sync --delete . \
    s3://"${S3_BUCKET_NAME}"/ \
    --exclude "*" \
    --include "index.html" \
    --include "data/output/*.json" \
    --include "resources/*"

  echo
  echo 'Done!'
}

main
