<?php
// Keep these tests compatible with PHP 5.3 and independent of external services.
$checks = array(
    'amf' => function () {
        $values = array(
            array('native', 'php', 5, true),
            array(-2147483649 => 'negative', 'name' => 'value', 0 => array('nested'))
        );
        // AMF0 and AMF3, decoding objects as associative arrays.
        foreach (array(0, 1) as $flags) {
            foreach ($values as $value) {
                if (amf_decode(amf_encode($value, $flags), 4) != $value) {
                    throw new Exception('AMF round-trip failed');
                }
            }
        }
        $builder = amf_sb_new();
        amf_sb_append($builder, array('a', array('b', 'c')));
        if (amf_sb_as_string($builder) !== 'abc') {
            throw new Exception('AMF string builder failed');
        }
    },
    'igbinary' => function () {
        $value = array('native', 'php', 5, true);
        if (igbinary_unserialize(igbinary_serialize($value)) !== $value) {
            throw new Exception('igbinary round-trip failed');
        }
    },
    'apcu' => function () {
        $value = array('native', 'php', 5, true);
        if (!apcu_store('native-build', $value) || apcu_fetch('native-build') !== $value) {
            throw new Exception('APCu store/fetch failed');
        }
        apcu_delete('native-build');
    },
    'dbase' => function () {
        $path = tempnam(sys_get_temp_dir(), 'dbase');
        unlink($path);
        $db = dbase_create($path, array(array('VALUE', 'N', 10, 2)));
        if (!$db || !dbase_add_record($db, array(12.5))) {
            throw new Exception('dBase numeric record creation failed');
        }
        if (!dbase_replace_record($db, array(42.25), 1)) {
            throw new Exception('dBase numeric record update failed');
        }
        $record = dbase_get_record($db, 1);
        if (abs($record[0] - 42.25) > 0.00001) {
            throw new Exception('dBase numeric record round-trip failed');
        }
        dbase_close($db);
        unlink($path);
    },
    'amqp' => function () {
        $connection = new AMQPConnection();
        $connection->setHost('localhost');
        if ($connection->getHost() !== 'localhost') {
            throw new Exception('AMQP connection configuration failed');
        }
        $timestamp = new AMQPTimestamp(4294967296);
        if ($timestamp->getTimestamp() !== '4294967296') {
            throw new Exception('AMQP 64-bit timestamp failed');
        }
    },
    'redis' => function () {
        $redis = new Redis();
        if ($redis->isConnected()) {
            throw new Exception('Redis unexpectedly connected');
        }
    },
    'http' => function () {
        $request = new http\Client\Request('GET', 'https://example.com');
        if ($request->getRequestMethod() !== 'GET') {
            throw new Exception('HTTP request construction failed');
        }
    }
);
if (isset($argv[1])) {
    if (!isset($checks[$argv[1]])) {
        throw new Exception('Unknown extension check: ' . $argv[1]);
    }
    $checks = array($argv[1] => $checks[$argv[1]]);
}
foreach ($checks as $name => $check) {
    echo 'Checking ' . $name . "\n";
    $check();
}
echo "Legacy extension behavior checks passed\n";
