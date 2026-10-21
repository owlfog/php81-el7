<?php
// No external services: validate ABI loading and local work by old PECL modules.
function check(bool $ok, string $what): void {
    if (!$ok) { fwrite(STDERR, "Failed: $what\n"); exit(1); }
}
foreach (['amqp', 'bcmath', 'curl', 'gd', 'igbinary', 'intl', 'mcrypt', 'memcache',
          'memcached', 'msgpack', 'mysqli', 'oci8', 'pdo_oci', 'pdo_pgsql',
          'rdkafka', 'redis', 'soap', 'sodium', 'xhprof', 'zip', 'opentelemetry', 'Zend OPcache'] as $ext) {
    check(extension_loaded($ext), "extension $ext");
}
check(str_starts_with(oci_client_version(), '21.16.'), 'Oracle client 21.16');
$curl = curl_init();
foreach (['CURL_SSLVERSION_TLSv1_0' => 4, 'CURL_SSLVERSION_TLSv1_1' => 5,
          'CURL_SSLVERSION_TLSv1_2' => 6] as $name => $value) {
    check(defined($name), "curl constant $name");
    check(constant($name) === $value, "curl value $name");
    check(curl_setopt($curl, CURLOPT_SSLVERSION, constant($name)), "curl selector $name");
}
curl_close($curl);
$value = ['php' => 81, 'nested' => [null, true, 'тест']];
check(igbinary_unserialize(igbinary_serialize($value)) === $value, 'igbinary');
check(msgpack_unpack(msgpack_pack($value)) === $value, 'msgpack');
check(bcadd('0.1', '0.2', 1) === '0.3', 'bcmath');
check(Normalizer::normalize("e\u{0301}") === 'é', 'intl');
$db = new PDO('sqlite::memory:');
check($db->query('SELECT 81')->fetchColumn() == 81, 'PDO sqlite');
$image = imagecreatetruecolor(1, 1);
check($image !== false, 'gd');
imagedestroy($image);
new Redis(); new Memcache(); new Memcached(); new AMQPConnection();
new RdKafka\Conf();
xhprof_enable();
check(is_array(xhprof_disable()), 'xhprof');
$observed = [];
$probeCount = 0;
// Remi enables OPcache for CLI. Keep a side effect so it cannot inline away
// the function call whose observer hooks this test is checking.
function php81_probe(): int { global $probeCount; return ++$probeCount; }
OpenTelemetry\Instrumentation\hook(null, 'php81_probe',
    function () use (&$observed) { $observed[] = 'pre'; },
    function () use (&$observed) { $observed[] = 'post'; });
check(php81_probe() === 1 && $observed === ['pre', 'post'], 'OpenTelemetry hooks');
echo "Extensions: loaded; local functionality passed.\n";
