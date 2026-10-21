#!/usr/bin/env bash
set -euo pipefail

PHP="${PHP:-/opt/remi/php81/root/usr/bin/php}"
command -v openssl >/dev/null || { echo 'OpenSSL CLI is required for the TLS fixture' >&2; exit 1; }
tls_dir=$(mktemp -d /tmp/php81-curl-tls.XXXXXX)
tls_pid=
cleanup() {
  if [[ -n "$tls_pid" ]]; then
    kill "$tls_pid" 2>/dev/null || true
    wait "$tls_pid" 2>/dev/null || true
  fi
  rm -rf "$tls_dir"
}
trap cleanup EXIT

# Local container-only fixture: require a real TLS 1.2 handshake with CA and
# hostname verification enabled. No application credentials or external API.
cat > "$tls_dir/openssl.cnf" <<'CONF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = root
[dn]
CN = PHP81 EL7 TLS test root
[root]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
CONF
openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 1 \
  -config "$tls_dir/openssl.cnf" -keyout "$tls_dir/ca-key.pem" \
  -out "$tls_dir/ca.pem" > "$tls_dir/certificate.log" 2>&1
cat > "$tls_dir/server.cnf" <<'CONF'
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost
CONF
openssl req -new -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' \
  -keyout "$tls_dir/key.pem" -out "$tls_dir/server.csr" \
  >> "$tls_dir/certificate.log" 2>&1
openssl x509 -req -sha256 -days 1 -in "$tls_dir/server.csr" \
  -CA "$tls_dir/ca.pem" -CAkey "$tls_dir/ca-key.pem" -CAcreateserial \
  -extfile "$tls_dir/server.cnf" -out "$tls_dir/cert.pem" \
  >> "$tls_dir/certificate.log" 2>&1
openssl s_server -accept 19082 -tls1_2 -www \
  -cert "$tls_dir/cert.pem" -key "$tls_dir/key.pem" \
  > "$tls_dir/server.log" 2>&1 &
tls_pid=$!

cat > "$tls_dir/request.php" <<'PHP'
<?php
if (!extension_loaded('curl') || !defined('CURL_SSLVERSION_TLSv1_2')) {
    fwrite(STDERR, "Missing curl/TLS 1.2 constant\n");
    exit(1);
}
$curl = curl_init('https://localhost:19082/');
if (!curl_setopt_array($curl, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_PROXY => '',
    CURLOPT_IPRESOLVE => CURL_IPRESOLVE_V4,
    CURLOPT_CONNECTTIMEOUT => 2,
    CURLOPT_TIMEOUT => 5,
    CURLOPT_SSLVERSION => CURL_SSLVERSION_TLSv1_2,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    CURLOPT_CAINFO => $argv[1],
])) {
    fwrite(STDERR, "Unable to configure curl TLS 1.2\n");
    exit(1);
}
for ($attempt = 0; $attempt < 50; ++$attempt) {
    $body = curl_exec($curl);
    if ($body !== false || curl_errno($curl) !== CURLE_COULDNT_CONNECT) {
        break;
    }
    usleep(100000);
}
if ($body === false || curl_getinfo($curl, CURLINFO_HTTP_CODE) !== 200
    || curl_getinfo($curl, CURLINFO_SSL_VERIFYRESULT) !== 0
    || strpos($body, 'TLSv1.2') === false) {
    fwrite(STDERR, 'TLS 1.2 request failed: ' . curl_error($curl) . "\n");
    exit(1);
}
curl_close($curl);
echo "cURL: TLS 1.2 HTTPS request passed; certificate and hostname verified.\n";
PHP
if ! "$PHP" "$tls_dir/request.php" "$tls_dir/ca.pem"; then
  cat "$tls_dir/server.log" >&2
  exit 1
fi
