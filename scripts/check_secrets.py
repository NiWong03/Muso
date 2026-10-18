#!/usr/bin/env python3
"""Scan commit candidates or the index without printing credential values."""
import argparse
import pathlib
import re
import subprocess
import sys

PATTERNS = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'Google API key': rb'AIza[0-9A-Za-z_-]{30,}',
    'Google OAuth secret': rb'GOCSPX-[A-Za-z0-9_-]+',
    'OpenAI API key': rb'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}',
    'GitHub token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})',
    'AWS access ID': rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'Slack token': rb'\bxox[baprs]-[A-Za-z0-9-]{15,}',
    'JWT': rb'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    'credential URL': rb'https?://[^\s/"<>]+:[^\s/"<>]+@',
    'literal credential': rb'''(?i)(?:api[_-]?key|client[_-]?secret|password|access[_-]?token|refresh[_-]?token)\s*["']?\s*[:=]\s*["']([A-Za-z0-9_+/=-]{20,})["']''',
}

def git(*args):
    return subprocess.check_output(['git', *args])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true', help='scan all files in the index')
    parser.add_argument('--history', action='store_true', help='also scan all reachable Git blobs')
    args = parser.parse_args()
    root = pathlib.Path(git('rev-parse', '--show-toplevel').decode().strip())
    candidates = git('ls-files', '-z', '--cached') if args.staged else git('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    failures = []
    count = 0

    def scan(label, data):
        nonlocal count
        count += 1
        # Image/binary blobs are not text credential files.
        if b'\0' in data[:8192]:
            return
        for kind, pattern in PATTERNS.items():
            for match in re.finditer(pattern, data):
                line = data[:match.start()].count(b'\n') + 1
                failures.append(f'{label}:{line}: {kind} [value withheld]')

    for raw in sorted(set(candidates.split(b'\0')) - {b''}):
        name = raw.decode()
        if args.staged:
            scan(name, git('show', ':' + name))
        elif (root / name).is_file():
            scan(name, (root / name).read_bytes())
    if args.history:
        for record in git('rev-list', '--objects', '--all').decode().splitlines():
            oid, _, name = record.partition(' ')
            if git('cat-file', '-t', oid).strip() == b'blob':
                scan('history/' + oid[:10] + '/' + name, git('cat-file', 'blob', oid))
    for failure in failures:
        print(failure)
    print(f'Scanned {count} files/blobs; {len(failures)} potential credential findings.')
    return 1 if failures else 0

if __name__ == '__main__':
    sys.exit(main())
