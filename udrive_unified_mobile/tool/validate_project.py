from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
errors = []

for dart in (root / 'lib').rglob('*.dart'):
    text = dart.read_text(encoding='utf-8')
    stack = []
    pairs = {')': '(', ']': '[', '}': '{'}
    opening = set(pairs.values())
    in_single = in_double = in_line = in_block = False
    escaped = False
    i = 0
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if in_line:
            if ch == '\n': in_line = False
            i += 1; continue
        if in_block:
            if ch == '*' and nxt == '/': in_block = False; i += 2; continue
            i += 1; continue
        if not in_single and not in_double:
            if ch == '/' and nxt == '/': in_line = True; i += 2; continue
            if ch == '/' and nxt == '*': in_block = True; i += 2; continue
        if escaped:
            escaped = False; i += 1; continue
        if ch == '\\' and (in_single or in_double):
            escaped = True; i += 1; continue
        if ch == "'" and not in_double: in_single = not in_single; i += 1; continue
        if ch == '"' and not in_single: in_double = not in_double; i += 1; continue
        if in_single or in_double: i += 1; continue
        if ch in opening: stack.append((ch, i))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                errors.append(f'{dart}: unmatched {ch} at {i}')
                break
            stack.pop()
        i += 1
    if stack:
        errors.append(f'{dart}: unclosed {stack[-1][0]} at {stack[-1][1]}')

for dart in (root / 'lib').rglob('*.dart'):
    text = dart.read_text(encoding='utf-8')
    for match in re.finditer(r"import\s+'([^']+)';", text):
        value = match.group(1)
        if value.startswith('.'):
            target = (dart.parent / value).resolve()
            if not target.exists(): errors.append(f'{dart}: missing import {value}')

if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print('Static delimiter/import checks passed for all Dart files.')

strings_file = root / 'lib/core/localization/app_strings.dart'
strings_text = strings_file.read_text(encoding='utf-8')
en_match = re.search(r"'en':\s*\{(.*?)\n\s*\},\n\s*'ur':", strings_text, re.S)
ur_match = re.search(r"'ur':\s*\{(.*?)\n\s*\},\n\s*\};", strings_text, re.S)
if not en_match or not ur_match:
    raise SystemExit('Could not parse English/Urdu localization maps.')
key_pattern = re.compile(r"^\s*'([^']+)'\s*:", re.M)
en_keys = set(key_pattern.findall(en_match.group(1)))
ur_keys = set(key_pattern.findall(ur_match.group(1)))
used_keys = set()
for dart in (root / 'lib').rglob('*.dart'):
    used_keys.update(re.findall(r"\.tr\('([^']+)'\)", dart.read_text(encoding='utf-8')))
missing_en = sorted(used_keys - en_keys)
missing_ur = sorted(used_keys - ur_keys)
if missing_en or missing_ur or en_keys != ur_keys:
    raise SystemExit(
        f'Localization mismatch. Missing EN={missing_en}; Missing UR={missing_ur}; '
        f'EN-only={sorted(en_keys - ur_keys)}; UR-only={sorted(ur_keys - en_keys)}'
    )

inactive_patterns = [
    re.compile(r'onPressed\s*:\s*\(\)\s*\{\s*\}'),
    re.compile(r'onTap\s*:\s*\(\)\s*\{\s*\}'),
    re.compile(r'onChanged\s*:\s*\([^)]*\)\s*\{\s*\}'),
]
inactive = []
for dart in (root / 'lib').rglob('*.dart'):
    dart_text = dart.read_text(encoding='utf-8')
    for pattern in inactive_patterns:
        for match in pattern.finditer(dart_text):
            inactive.append(f'{dart}:{dart_text.count(chr(10), 0, match.start()) + 1}')
if inactive:
    raise SystemExit('Inactive empty callbacks found: ' + ', '.join(inactive))

print('Localization parity and active callback checks passed.')
