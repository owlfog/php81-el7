#!/usr/bin/env bash
set -euo pipefail

: "${RPM_GPG_NAME:?Set RPM_GPG_NAME to the GPG key identity used for RPM signing}"

RELEASE_SUFFIX="${RELEASE_SUFFIX:-rhcustom}"
GNUPGHOME="${GNUPGHOME:-$PWD/build/gnupg-sign}"
PUBLIC_KEY_OUT="${RPM_GPG_PUBLIC_KEY_OUT:-dist/RPM-GPG-KEY-rosa-khutor}"

mkdir -p "$GNUPGHOME" dist
chmod 700 "$GNUPGHOME"

if [[ -n "${RPM_GPG_PRIVATE_KEY_B64:-}" ]]; then
  printf '%s' "$RPM_GPG_PRIVATE_KEY_B64" | base64 -d | \
    GNUPGHOME="$GNUPGHOME" gpg --batch --import ||
    GNUPGHOME="$GNUPGHOME" gpg --batch --list-secret-keys "$RPM_GPG_NAME" >/dev/null 2>&1
elif [[ -n "${RPM_GPG_PRIVATE_KEY_FILE:-}" ]]; then
  GNUPGHOME="$GNUPGHOME" gpg --batch --import "$RPM_GPG_PRIVATE_KEY_FILE" ||
    GNUPGHOME="$GNUPGHOME" gpg --batch --list-secret-keys "$RPM_GPG_NAME" >/dev/null 2>&1
elif ! GNUPGHOME="$GNUPGHOME" gpg --batch --list-secret-keys "$RPM_GPG_NAME" >/dev/null 2>&1; then
  echo "key '$RPM_GPG_NAME' not found — set RPM_GPG_PRIVATE_KEY_B64 or RPM_GPG_PRIVATE_KEY_FILE" >&2
  exit 1
fi

shopt -s nullglob
RPM_FILES=(dist/rpms/*."$RELEASE_SUFFIX".*.rpm dist/srpms/*."$RELEASE_SUFFIX".src.rpm)
if [[ "${#RPM_FILES[@]}" -eq 0 ]]; then
  echo "No RPM files matching *.$RELEASE_SUFFIX.*.rpm" >&2
  exit 1
fi

GNUPGHOME="$GNUPGHOME" rpmsign --addsign \
  --define "_signature gpg" \
  --define "_gpg_name $RPM_GPG_NAME" \
  --define "_gpg_digest_algo sha256" \
  --define "__gpg /usr/bin/gpg2" \
  "${RPM_FILES[@]}"

GNUPGHOME="$GNUPGHOME" gpg --batch --armor --export "$RPM_GPG_NAME" > "$PUBLIC_KEY_OUT"

RPM_CHECK_DB="$GNUPGHOME/rpmdb"
mkdir -p "$RPM_CHECK_DB"
rpm --define "_dbpath $RPM_CHECK_DB" --initdb
rpm --define "_dbpath $RPM_CHECK_DB" --import "$PUBLIC_KEY_OUT"
rpm --define "_dbpath $RPM_CHECK_DB" -K "${RPM_FILES[@]}"

(cd dist && sha256sum rpms/*.rpm srpms/*.rpm > SHA256SUMS)

echo "RPM public key: $PWD/$PUBLIC_KEY_OUT"
