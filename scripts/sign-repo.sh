#!/usr/bin/env bash
set -euo pipefail

: "${RPM_GPG_NAME:?Set RPM_GPG_NAME to the GPG key identity used for repo signing}"

GNUPGHOME="${GNUPGHOME:-$PWD/build/gnupg-sign}"
REPO_DIR="${REPO_DIR:-dist/repo/el7/x86_64}"
PUBLIC_KEY_OUT="${RPM_GPG_PUBLIC_KEY_OUT:-dist/RPM-GPG-KEY-rosa-khutor}"
REPOMD="$REPO_DIR/repodata/repomd.xml"

mkdir -p "$GNUPGHOME" dist
chmod 700 "$GNUPGHOME"

# gpg --import exits 2 on EL7 when the key is already present; fall back to
# verifying the key is actually there rather than aborting via set -e.
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

if [[ ! -f "$REPOMD" ]]; then
  echo "Repo metadata not found: $REPOMD" >&2
  exit 1
fi

# --passphrase-fd bypasses pinentry in headless Docker (same path as rpmsign's %__gpg_sign_cmd).
GNUPGHOME="$GNUPGHOME" gpg --batch --yes --armor --detach-sign \
  --digest-algo SHA256 \
  --passphrase-fd 3 \
  --local-user "$RPM_GPG_NAME" \
  "$REPOMD" 3< <(printf '%s' "${RPM_GPG_PASSPHRASE:-}")

GNUPGHOME="$GNUPGHOME" gpg --batch --armor --export "$RPM_GPG_NAME" > "$PUBLIC_KEY_OUT"

echo "Repo metadata signature: $PWD/$REPOMD.asc"
echo "RPM public key: $PWD/$PUBLIC_KEY_OUT"
