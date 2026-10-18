#!/usr/bin/env python3
"""Usage: check_network.py APP I686_CLANG PREPARED_SUPPORT WORK_DIRECTORY.

Runs a 32-bit Winsock client/server under the bundled runtime against host
echo servers. This checks transport, not original-game multiplayer acceptance.
"""
import os
import re
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import threading
import time

app, compiler, support, work = map(Path, sys.argv[1:])
work.mkdir(parents=True, exist_ok=True)
exe = work.resolve() / 'network-probe.exe'
subprocess.run([str(compiler), '-O2', '-Wall', '-Wextra', '-static',
                str(Path(__file__).with_name('network_probe.c')), '-lws2_32', '-o', str(exe)], check=True)
tcp = socket.socket()
tcp.bind(('127.0.0.1', 0))
tcp.listen(1)
tcp.settimeout(180)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(('127.0.0.1', 0))
udp.settimeout(180)
errors = []


def echo_tcp():
    try:
        with tcp.accept()[0] as connection:
            connection.settimeout(10)
            connection.sendall(connection.recv(128))
    except Exception as error:
        errors.append(str(error))


def echo_udp():
    try:
        data, peer = udp.recvfrom(128)
        udp.sendto(data, peer)
    except Exception as error:
        errors.append(str(error))


threads = [threading.Thread(target=echo_tcp, daemon=True), threading.Thread(target=echo_udp, daemon=True)]
for thread in threads:
    thread.start()
resources = app.resolve() / 'Contents/Resources'
runtime = resources / 'runtime'
arm64 = runtime.is_dir()
env = {k: os.environ[k] for k in ('HOME', 'USER', 'LANG', 'TMPDIR') if k in os.environ}
env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin', WINEDEBUG='-all',
           WINEDLLOVERRIDES='mscoree,mshtml=;winemenubuilder.exe=d')
if arm64:
    env.update(WINEPREFIX=str(support.resolve() / 'Prefix-arm64'),
               HADRON_SUPPORT=str(support.resolve() / 'ARM64'), HADRON_PROGRAM='1',
               FEX_DISKCACHE='0', FEX_SMCCHECKS='mtrack',
               HADRON_APP_NAME='NTSD network probe')
    command = [str(runtime / 'scripts/play'), 'ntsd-network-probe', str(exe)]
    server = runtime / 'dist/bin/wineserver'
else:
    env['WINEPREFIX'] = str(support.resolve() / 'Prefix')
    command = [str(resources / 'wine/bin/wine'), str(exe)]
    server = resources / 'wine/bin/wineserver'
log = (work / 'network-runtime.log').open('w')
process = subprocess.Popen(command + [str(tcp.getsockname()[1]), str(udp.getsockname()[1])],
                           env=env, stdout=subprocess.PIPE, stderr=log)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
output = b''
deadline = time.monotonic() + 180
port = None
try:
    while time.monotonic() < deadline:
        if not selector.select(timeout=1):
            if process.poll() is not None:
                break
            continue
        chunk = os.read(process.stdout.fileno(), 4096)
        if not chunk:
            break
        output += chunk
        for line in output.splitlines():
            if line.startswith(b'LISTEN_PORT=') and port is None:
                port = int(line.split(b'=')[1])
                # Inspect the actual guest host process while it waits in accept.
                # Sampling is brief and is not a performance measurement.
                sample = work / 'native-process-sample.txt'
                subprocess.run(['/usr/bin/sample', str(process.pid), '1', '10', '-file', str(sample)],
                               stdout=log, stderr=log, check=True)
                expected = r'(?:ARM64|ARM-64 \(Native\))' if arm64 else r'X86-64(?: \(translated\))?'
                assert re.search(r'^Code Type:\s+' + expected + r'\s*$', sample.read_text(), re.M), \
                    'Probe host architecture does not match the selected runtime'
                # Bind was INADDR_ANY: test an inbound connection from the host.
                with socket.create_connection(('127.0.0.1', port), timeout=10) as connection:
                    connection.sendall(b'host-to-Windows')
                    assert connection.recv(128) == b'host-to-Windows'
    status = process.wait(timeout=10)
    print(output.decode(errors='replace'))
    assert status == 0 and port is not None and not errors, (status, errors)
finally:
    if process.poll() is None:
        subprocess.run([str(server), '-k'], env=env, check=False)
        process.wait(timeout=10)
    log.close()
    selector.close()
    tcp.close()
    udp.close()
