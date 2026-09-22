<?php
require_once 'PEAR/XMLParser.php';

function check_pear($condition, $message)
{
    if (!$condition) {
        throw new Exception($message);
    }
}

$parser = new PEAR_XMLParser();
$xml = '<?xml version="1.0" encoding="UTF-8"?>'
    . '<dependencies><group hint="PEAR&apos;s &quot;installer&quot; &amp; &lt;tool&gt;">'
    . '<package>foo &amp; bar</package></group></dependencies>';
check_pear($parser->parse($xml) === true, 'PEAR XML parse failed');
$data = $parser->getData();
check_pear(!isset($data['_content']), 'Attribute entities leaked into element text');
check_pear($data['group']['attribs']['hint'] === 'PEAR\'s "installer" & <tool>', 'Attribute value changed');
check_pear($data['group']['package'] === 'foo & bar', 'Element value changed');
$xml = '<root><!-- &amp; --><?test &apos;?><value><![CDATA[&apos; &amp;]]></value></root>';
check_pear($parser->parse($xml) === true, 'Literal XML parse failed');
$data = $parser->getData();
check_pear($data['value'] === '&apos; &amp;', 'CDATA content changed');

if (version_compare(PHP_VERSION, '5.4', '>=')) {
    require_once 'PEAR/Builder.php';
    require_once 'PEAR/Frontend.php';
    $ui = PEAR_Frontend::singleton('PEAR_Frontend_CLI');
    $builder = new PEAR_Builder('with-example="/tmp/a b" enable-feature="no"', $ui);
    check_pear($builder->_parsed_configure_options === array(
        'with-example' => '/tmp/a b', 'enable-feature' => 'no'
    ), 'Named configure options were not preserved');
}
echo "PEAR XML and configure-option checks passed\n";
