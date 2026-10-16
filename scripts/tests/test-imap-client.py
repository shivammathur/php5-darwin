#!/usr/bin/env python3
"""Verify the built extension still selects its GSSAPI client authenticator."""
from pathlib import Path
import socket
import subprocess
import sys
import threading

php, extension = sys.argv[1:]
commands = []
errors = []
server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen(1)
server.settimeout(20)


def serve():
    try:
        conn, _ = server.accept()
        with conn:
            conn.settimeout(15)
            io = conn.makefile('rwb', buffering=0)
            io.write(b'* OK [CAPABILITY IMAP4rev1 AUTH=GSSAPI LOGINDISABLED] test\r\n')
            while True:
                line = io.readline().decode().strip()
                if not line:
                    break
                commands.append(line)
                parts = line.split()
                tag = parts[0]
                if len(parts) > 1 and parts[1].upper() == 'CAPABILITY':
                    io.write(b'* CAPABILITY IMAP4rev1 AUTH=GSSAPI LOGINDISABLED\r\n')
                    io.write((tag + ' OK capabilities\r\n').encode())
                elif len(parts) > 2 and parts[1:3] == ['AUTHENTICATE', 'GSSAPI']:
                    io.write(b'+ \r\n')
                    commands.append(io.readline().decode().strip())
                    io.write((tag + ' NO no test credentials\r\n').encode())
                elif len(parts) > 1 and parts[1].upper() == 'LOGOUT':
                    io.write(b'* BYE done\r\n')
                    io.write((tag + ' OK logout\r\n').encode())
                    break
                else:
                    io.write((tag + ' BAD unexpected command\r\n').encode())
    except Exception as error:
        errors.append(str(error))


worker = threading.Thread(target=serve, daemon=True)
worker.start()
try:
    subprocess.run([php, '-n', '-d', 'extension=' + extension,
                    str(Path(__file__).with_name('imap-client.php')),
                    str(server.getsockname()[1])], check=True, timeout=35)
    worker.join(20)
finally:
    server.close()
print('IMAP transcript:', commands)
assert not errors, errors
assert not worker.is_alive(), 'IMAP server did not terminate'
assert any('AUTHENTICATE GSSAPI' in line for line in commands), 'GSSAPI client was not selected'
