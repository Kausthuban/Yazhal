#!/usr/bin/env python3
"""Version-aware OSV audit of hosted dependencies in the checked-in pub lock.
Run from the repository root with Python 3 and PyYAML installed. Network required.
Vendored source and native/platform dependency review remain separate tasks.
"""
import json
from pathlib import Path
import urllib.request
import yaml

lock = yaml.safe_load(Path('pubspec.lock').read_text())
queries = []
for name, package in sorted(lock['packages'].items()):
    if package['source'] == 'hosted':
        queries.append({'package': {'name': name, 'ecosystem': 'Pub'}, 'version': package['version']})
request = urllib.request.Request('https://api.osv.dev/v1/querybatch', data=json.dumps({'queries': queries}).encode(), headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(request, timeout=60) as response:
    results = json.load(response)['results']
findings = []
for query, result in zip(queries, results, strict=True):
    for vulnerability in result.get('vulns', []):
        findings.append({'package': query['package']['name'], 'version': query['version'], 'advisory': vulnerability['id']})
print(json.dumps({'packages_queried': len(queries), 'findings': findings}, indent=2))
raise SystemExit(1 if findings else 0)
