<?php
// PHP 5's SAX adapter emits predefined entities in attributes as element text
// with current libxml2. Numeric references preserve the same XML value without
// that callback bug. Do not change literal content in CDATA, comments or PIs.
if ($argc !== 2) {
    fwrite(STDERR, "Usage: patch-pear-xml.php <bootstrap.phar|PEAR/XMLParser.php>\n");
    exit(1);
}
$path = $argv[1];
$archive = null;
if (substr($path, -5) === '.phar') {
    $archive = new Phar($path);
    $source = $archive['PEAR/XMLParser.php']->getContent();
} else {
    $source = file_get_contents($path);
}
$marker = '// Normalize predefined entities for legacy PHP/libxml2.';
if (strpos($source, $marker) !== false) {
    exit(0);
}
$needle = '        $xp = xml_parser_create($this->encoding);';
if (substr_count($source, $needle) !== 1) {
    fwrite(STDERR, "Unexpected PEAR XML parser\n");
    exit(1);
}
$replacement = <<<'PHP'
        // Normalize predefined entities for legacy PHP/libxml2.
        $data = preg_replace_callback(
            '/<!\[CDATA\[.*?\]\]>|<!--.*?-->|<\?.*?\?>|&(?:amp|lt|gt|apos|quot);/s',
            function ($match) {
                if ($match[0][0] !== '&') {
                    return $match[0];
                }
                return strtr($match[0], array(
                    '&amp;' => '&#38;', '&lt;' => '&#60;', '&gt;' => '&#62;',
                    '&apos;' => '&#39;', '&quot;' => '&#34;'
                ));
            },
            $data
        );
        $xp = xml_parser_create($this->encoding);
PHP;
$source = str_replace($needle, $replacement, $source);
if ($archive !== null) {
    $archive['PEAR/XMLParser.php'] = $source;
} elseif (file_put_contents($path, $source) === false) {
    exit(1);
}
