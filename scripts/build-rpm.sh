#!/usr/bin/env bash
set -euo pipefail

PHP_RELEASE="${PHP_RELEASE:-7}"
BUILD_JOBS="${BUILD_JOBS:-2}"
[[ "$PHP_RELEASE" =~ ^[0-9]+$ && "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || exit 2
RPM_TOPDIR="$PWD/build/rpmbuild"
sha256sum -c packaging/SHA256SUMS
mkdir -p "$RPM_TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} build/cache dist/rpms dist/srpms
TARBALL="$PWD/build/cache/php-8.1.34.tar.xz"
if [[ ! -f "$TARBALL" ]]; then
  curl -fL --retry 3 --connect-timeout 30 --max-time 600 \
    https://www.php.net/distributions/php-8.1.34.tar.xz -o "$TARBALL.tmp"
  mv "$TARBALL.tmp" "$TARBALL"
fi
echo "ffa9e0982e82eeaea848f57687b425ed173aa278fe563001310ae2638db5c251  $TARBALL" | sha256sum -c -
mkdir -p "$RPM_TOPDIR/gnupg"
chmod 700 "$RPM_TOPDIR/gnupg"
if ! gpg2 --homedir "$RPM_TOPDIR/gnupg" --batch --import packaging/SOURCES/php-keyring.gpg; then
  # EL7 GnuPG does not understand several newer keys in the upstream bundle.
  # The actual release signer must still have been imported successfully.
  gpg2 --homedir "$RPM_TOPDIR/gnupg" --batch --list-keys \
    39B641343D8C104B2B146DC3F9C39DC0B9698544 >/dev/null
fi
gpg2 --homedir "$RPM_TOPDIR/gnupg" --batch \
  --verify packaging/SOURCES/php-8.1.34.tar.xz.asc "$TARBALL"
cp packaging/SOURCES/* "$RPM_TOPDIR/SOURCES/"
cp packaging/patches/*.patch "$RPM_TOPDIR/SOURCES/"
cp "$TARBALL" "$RPM_TOPDIR/SOURCES/"
sed "s/@RELEASE@/$PHP_RELEASE/g" packaging/SPECS/php.spec.in > "$RPM_TOPDIR/SPECS/php.spec"

# Keep all Remi API/ABI checks, source signature checks and regression tests.
rpmbuild --define "_topdir $RPM_TOPDIR" --define 'scl php81' \
  --define 'dist .el7' --define "_smp_mflags -j$BUILD_JOBS" \
  --with oci8 -ba "$RPM_TOPDIR/SPECS/php.spec" 2>&1 | tee build/build.log

# Publish only this invocation's release, never a stale RPM from an old build.
find "$RPM_TOPDIR/RPMS" -type f -name "php81-php*-8.1.34-$PHP_RELEASE.el7.rhcustom.*.rpm" \
  ! -name '*debuginfo*' -exec cp -f {} dist/rpms/ \;
cp "$RPM_TOPDIR/SRPMS/php81-php-8.1.34-$PHP_RELEASE.el7.rhcustom.src.rpm" dist/srpms/
(cd dist && sha256sum rpms/*.rpm srpms/*.rpm > SHA256SUMS)
