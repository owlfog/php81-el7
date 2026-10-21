#!/usr/bin/env bash
set -euo pipefail

PHP=/opt/remi/php81/root/usr/bin/php
FPM=/opt/remi/php81/root/usr/sbin/php-fpm
PHP_RELEASE="${PHP_RELEASE:-7}"
[[ "$PHP_RELEASE" =~ ^[0-9]+$ ]] || exit 2
# Exercise a legacy collection runtime; build macros are not needed here.
rpm -e php81-build
yum -y downgrade php81-runtime-8.1-1.el7.remi
core=(bcmath cli common devel fpm gd intl mbstring mysqlnd oci8 opcache pdo pgsql process soap sodium xml)
pecl=(amqp-2.1.2-1 memcache-8.2-1
      memcached-3.2.0-1 msgpack-2.2.0~RC2-1 rdkafka6-6.0.3-2
      redis5-5.3.7-1 xhprof-2.3.9-1 zip-1.22.3-1)
baseline=(php81-8.1-1.el7.remi php81-php-pear-1.10.15-3.el7.remi.noarch)
for name in "${core[@]}"; do baseline+=("php81-php-$name-8.1.29-1.el7.remi"); done
for name in "${pecl[@]}"; do baseline+=("php81-php-pecl-$name.el7.remi"); done
# These two original Remi RPMs were pruned from its current EL7 archive.
# The mirror retained them: require both pinned bytes and Remi's signature.
for entry in \
  'php81-php-pecl-igbinary-3.2.12-1.el7.remi.x86_64.rpm:f3b98633c27b4bf408b932f4fb3f1278ffe63650f646b27cd5c04e8d59ace7e6' \
  'php81-php-pecl-mcrypt-1.0.5-1.el7.remi.x86_64.rpm:18956bb0ca523ee62a6b052f864524cd739d2443ae0a4528929850003c73f82c'; do
  file="${entry%%:*}"
  hash="${entry#*:}"
  curl -fL --retry 3 --connect-timeout 30 --max-time 180 \
    "https://repo.extreme-ix.org/remi/enterprise/7/remi/x86_64/$file" -o "/tmp/$file"
  echo "$hash  /tmp/$file" | sha256sum -c -
  rpm -K "/tmp/$file"
  baseline+=("/tmp/$file")
done

# Install a legacy extension baseline, then update the core.
yum -y install "${baseline[@]}"
# Exercise an unmanaged PECL OpenTelemetry 1.2.1 module built against
# the old PHP, then keep the exact same .so through the core upgrade.
curl -fL --retry 3 --connect-timeout 30 --max-time 180 \
  https://pecl.php.net/get/opentelemetry-1.2.1.tgz -o /tmp/opentelemetry.tgz
echo 'de8315ed3299536f327360a37f03618ab8684c02fbf8dfd8f489c025d88a6498  /tmp/opentelemetry.tgz' | sha256sum -c -
tar -xzf /tmp/opentelemetry.tgz -C /tmp
(
  cd /tmp/opentelemetry-1.2.1
  /opt/remi/php81/root/usr/bin/phpize
  CFLAGS='-O2 -std=gnu99' ./configure --with-php-config=/opt/remi/php81/root/usr/bin/php-config
  make -j2
  make install
)
echo 'extension=opentelemetry.so' > /etc/opt/remi/php81/php.d/40-opentelemetry.ini
otel_hash=$(sha256sum /opt/remi/php81/root/usr/lib64/php/modules/opentelemetry.so)
"$PHP" scripts/test-extensions.php
"$PHP" -m | sort > /tmp/php81-modules-before
"$PHP" -r 'file_put_contents("/tmp/php81-curl-constants-before.json", json_encode(get_defined_constants(true)["curl"], JSON_THROW_ON_ERROR));'
rpm -qa 'php81-php-pecl-*' | sort > /tmp/php81-pecl-before
pool=/etc/opt/remi/php81/php-fpm.d/www.conf
echo '; php81-el7 configuration preservation test' >> "$pool"
pool_hash=$(sha256sum "$pool")
oom_code='register_shutdown_function(function () { file_put_contents("/tmp/php81-cli-cleanup", "ran"); }); str_repeat("x", 64 * 1024 * 1024);'
baseline_status=0
"$PHP" -d memory_limit=16M -r "$oom_code" > /tmp/php81-cli-before 2>&1 || baseline_status=$?
[[ "$baseline_status" -eq 255 && -f /tmp/php81-cli-cleanup ]]
rm /tmp/php81-cli-cleanup
rpms=()
for name in "${core[@]}"; do
  matches=(dist/rpms/"php81-php-$name-8.1.34-$PHP_RELEASE.el7.rhcustom.x86_64.rpm")
  [[ ${#matches[@]} -eq 1 && -f "${matches[0]}" ]] || { echo "Ambiguous or absent RPM: $name" >&2; exit 1; }
  rpms+=("${matches[0]}")
done
yum -y localupdate "${rpms[@]}"
[[ "$(sha256sum "$pool")" == "$pool_hash" ]]
[[ "$(sha256sum /opt/remi/php81/root/usr/lib64/php/modules/opentelemetry.so)" == "$otel_hash" ]]
"$PHP" -m | sort > /tmp/php81-modules-after
diff -u /tmp/php81-modules-before /tmp/php81-modules-after
rpm -qa 'php81-php-pecl-*' | sort > /tmp/php81-pecl-after
diff -u /tmp/php81-pecl-before /tmp/php81-pecl-after
[[ "$(rpm -q php81-runtime)" == 'php81-runtime-8.1-1.el7.remi.x86_64' ]]
"$PHP" -r 'if (PHP_VERSION !== "8.1.34") exit(1);'
patched_status=0
"$PHP" -d memory_limit=16M -r "$oom_code" > /tmp/php81-cli-after 2>&1 || patched_status=$?
[[ "$patched_status" -eq 1 && ! -e /tmp/php81-cli-cleanup ]]
grep -q 'Allowed memory size' /tmp/php81-cli-after
"$PHP" scripts/test-extensions.php
"$PHP" -r '
    $before = json_decode(file_get_contents("/tmp/php81-curl-constants-before.json"), true, 512, JSON_THROW_ON_ERROR);
    foreach ($before as $name => $value) {
        if (!defined($name) || constant($name) !== $value) {
            fwrite(STDERR, "Changed or missing curl constant: $name\n");
            exit(1);
        }
    }
    echo "cURL: all ", count($before), " baseline constants preserved.\n";
'
"$FPM" -t
./scripts/test-curl-tls.sh
if "$PHP" -m 2>&1 | grep -Ei 'unable to load|undefined symbol|startup:'; then exit 1; fi

mkdir -p /tmp/php81-fpm
chmod 755 /tmp/php81-fpm
cat > /tmp/php81-fpm/health.php <<'PHP'
<?php
header('Content-Type: text/plain');
echo 'healthy:', getmypid(), ':', PHP_VERSION;
PHP
cat > /tmp/php81-fpm/oom.php <<'PHP'
<?php
register_shutdown_function(function () { file_put_contents('/tmp/php81-fpm/unsafe-shutdown', 'ran'); });
ini_set('memory_limit', '16M');
$data = str_repeat('x', 64 * 1024 * 1024);
PHP
chmod 777 /tmp/php81-fpm
cat > /tmp/php81-fpm.conf <<'CONF'
[global]
daemonize = no
error_log = /tmp/php81-fpm.log
[test]
user = apache
group = apache
listen = 127.0.0.1:19081
pm = static
pm.max_children = 1
catch_workers_output = yes
php_admin_flag[session.upload_progress.enabled] = off
CONF
"$FPM" -y /tmp/php81-fpm.conf &
fpm_pid=$!
trap 'kill "$fpm_pid" 2>/dev/null || true; wait "$fpm_pid" 2>/dev/null || true' EXIT
request() {
  SCRIPT_FILENAME="/tmp/php81-fpm/$1.php" SCRIPT_NAME="/$1.php" REQUEST_METHOD=GET \
    cgi-fcgi -bind -connect 127.0.0.1:19081
}
for ((i=0; i<50; i++)); do
  if request health > /tmp/php81-health-before 2>/dev/null; then break; fi
  sleep 0.1
done
grep -q 'healthy:.*:8.1.34' /tmp/php81-health-before
before=$(tr -d '\r' < /tmp/php81-health-before | sed -n 's/^healthy:\([0-9]*\):.*/\1/p')
request oom > /tmp/php81-oom-response || true
for ((i=0; i<50; i++)); do
  request health > /tmp/php81-health-after 2>/dev/null || true
  after=$(tr -d '\r' < /tmp/php81-health-after | sed -n 's/^healthy:\([0-9]*\):.*/\1/p')
  [[ -n "$after" && "$after" != "$before" ]] && break
  sleep 0.1
done
[[ -n "$after" && "$after" != "$before" ]]
[[ ! -e /tmp/php81-fpm/unsafe-shutdown ]]
grep -q 'Allowed memory size' /tmp/php81-fpm.log
echo "FPM: OOM worker $before exited; replacement worker $after serves requests."
