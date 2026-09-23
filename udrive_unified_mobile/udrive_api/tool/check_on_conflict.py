"""Checks every ON CONFLICT against the index it needs.

Written after the API refused to start on deploy: migration 041 used
`ON CONFLICT (idempotency_key)` where the index behind it is *partial*
(`WHERE idempotency_key IS NOT NULL`). Postgres accepts a partial index as an
arbiter only when the statement repeats its predicate; otherwise it raises
42P10, the migration runner aborts, and the whole service fails to boot. One
missing WHERE cost a deployment.

The same fault was already sitting in `PaymentService.CreateAsync` against
`payments`, where it would have failed on every card payment.

Run from `udrive_api/`:

    python3 tool/check_on_conflict.py

Table-aware on purpose. An earlier version matched on column names alone and
reported three healthy statements — `driver_ride_request_decisions` has
`(ride_request_id, driver_profile_id)` as its PRIMARY KEY, but a *different*
table has a partial index on the same pair. A check that cries wolf gets
switched off, so it is better to miss a case than to invent three.
"""

import glob
import re
import sys

MIGRATIONS = sorted(glob.glob('Infrastructure/Persistence/Migrations/*.sql'))
CODE = sorted(glob.glob('Services/*.cs') + glob.glob('Controllers/*.cs'))


def normalise(columns: str) -> str:
    return re.sub(r'\s+', '', columns.lower())


def short(table: str) -> str:
    """`udrive.payments` and `payments` are the same table here."""
    return table.lower().rsplit('.', 1)[-1]


# ---------------------------------------------------------------- index catalogue
full: set[tuple[str, str]] = set()
partial: dict[tuple[str, str], str] = {}

for path in MIGRATIONS:
    text = open(path, encoding='utf-8').read()

    for match in re.finditer(
            r'CREATE\s+UNIQUE\s+INDEX[^;]*?\bON\s+([\w.]+)\s*\(([^)]*)\)'
            r'(?:\s*WHERE\s+([^;]+))?',
            text, re.I):
        table, columns, predicate = match.groups()
        key = (short(table), normalise(columns))
        if predicate:
            partial[key] = re.sub(r'\s+', ' ', predicate.strip())
        else:
            full.add(key)

    # Table-level constraints, attributed to the CREATE TABLE they sit inside.
    for block in re.finditer(
            r'CREATE\s+TABLE[^(]*?([\w.]+)\s*\((.*?)\n\);', text, re.I | re.S):
        table, body = block.groups()
        for match in re.finditer(r'(?:UNIQUE|PRIMARY\s+KEY)\s*\(([^)]*)\)', body, re.I):
            full.add((short(table), normalise(match.group(1))))
        for match in re.finditer(
                r'^\s*(\w+)\s+[^,\n]*?\b(?:UNIQUE|PRIMARY\s+KEY)\b', body, re.I | re.M):
            full.add((short(table), match.group(1).lower()))


# ------------------------------------------------------------------- statements
problems = 0
for path in MIGRATIONS + CODE:
    text = open(path, encoding='utf-8').read()

    for match in re.finditer(
            r'ON\s+CONFLICT\s*\(([^)]*)\)(\s*WHERE\s+([^\n]+?))?\s*DO\b',
            text, re.I):
        columns = normalise(match.group(1))
        states_predicate = match.group(3) is not None

        # The nearest INSERT INTO above this statement names the table.
        before = text[:match.start()]
        inserts = re.findall(r'INSERT\s+INTO\s+([\w.]+)', before, re.I)
        if not inserts:
            continue
        table = short(inserts[-1])

        key = (table, columns)
        if key in full or states_predicate:
            continue
        if key in partial:
            line = before.count('\n') + 1
            print(f'{path}:{line}: ON CONFLICT ({columns}) on {table} needs '
                  f'"WHERE {partial[key]}" — that index is partial')
            problems += 1

print('ON CONFLICT PROBLEMS:', problems)
sys.exit(1 if problems else 0)
