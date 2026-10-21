#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-dist/repo/el7/x86_64}"
RELEASE_SUFFIX="${RELEASE_SUFFIX:-rhcustom}"

mkdir -p "$REPO_DIR"
find "$REPO_DIR" -maxdepth 1 -type f -name '*.rpm' -delete
rm -rf "$REPO_DIR/repodata"

shopt -s nullglob
RPM_FILES=(dist/rpms/*."$RELEASE_SUFFIX".*.rpm)
if [[ "${#RPM_FILES[@]}" -eq 0 ]]; then
  echo "No RPM files matching dist/rpms/*.$RELEASE_SUFFIX.*.rpm" >&2
  exit 1
fi

cp -f "${RPM_FILES[@]}" "$REPO_DIR/"
createrepo --update "$REPO_DIR"

echo "Local yum repo: $PWD/$REPO_DIR"
