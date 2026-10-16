<?php
$mailbox = '{127.0.0.1:' . $argv[1] . '/imap/notls/norsh}INBOX';
$stream = @imap_open($mailbox, 'runtime-test', 'unused', OP_HALFOPEN, 1);
if ($stream) {
    imap_close($stream);
}
imap_errors();
imap_alerts();
?>
