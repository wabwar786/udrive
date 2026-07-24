from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
errors: list[str] = []


def check_delimiters(dart: Path) -> None:
    text = dart.read_text(encoding='utf-8')
    stack: list[tuple[str, int]] = []
    pairs = {')': '(', ']': '[', '}': '{'}
    opening = set(pairs.values())
    in_single = in_double = in_line = in_block = False
    escaped = False
    i = 0
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if in_line:
            if ch == '\n':
                in_line = False
            i += 1
            continue
        if in_block:
            if ch == '*' and nxt == '/':
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if not in_single and not in_double:
            if ch == '/' and nxt == '/':
                in_line = True
                i += 2
                continue
            if ch == '/' and nxt == '*':
                in_block = True
                i += 2
                continue
        if escaped:
            escaped = False
            i += 1
            continue
        if ch == '\\' and (in_single or in_double):
            escaped = True
            i += 1
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            i += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            i += 1
            continue
        if in_single or in_double:
            i += 1
            continue
        if ch in opening:
            stack.append((ch, i))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                errors.append(f'{dart}: unmatched {ch} at {i}')
                return
            stack.pop()
        i += 1
    if stack:
        errors.append(f'{dart}: unclosed {stack[-1][0]} at {stack[-1][1]}')


all_dart = list((root / 'lib').rglob('*.dart'))
for dart in all_dart:
    check_delimiters(dart)

for dart in all_dart:
    text = dart.read_text(encoding='utf-8')
    for match in re.finditer(r"import\s+'([^']+)';", text):
        value = match.group(1)
        if value.startswith('.'):
            target = (dart.parent / value).resolve()
            if not target.exists():
                errors.append(f'{dart}: missing import {value}')

localization_file = root / 'lib/core/localization/app_strings.dart'
localization_text = localization_file.read_text(encoding='utf-8')
used_keys: set[str] = set()
for dart in all_dart:
    if dart == localization_file:
        continue
    used_keys.update(re.findall(r"\.tr\('([^']+)'\)", dart.read_text(encoding='utf-8')))

language_blocks = re.findall(r"'([a-z]{2})': \{(.*?)\n    \},", localization_text, flags=re.S)
for code, block in language_blocks:
    keys = set(re.findall(r"'([^']+)':", block))
    missing = sorted(used_keys - keys)
    if missing:
        errors.append(f'Localization {code} missing keys: {", ".join(missing)}')

for dart in all_dart:
    text = dart.read_text(encoding='utf-8')
    for asset in re.findall(r"Image\.asset\(\s*['\"]([^'\"]+)['\"]", text):
        if not (root / asset).exists():
            errors.append(f'{dart}: missing asset {asset}')

empty_callback = re.compile(r"on(?:Pressed|Tap|Changed):\s*\([^)]*\)\s*\{\s*\}")
for dart in all_dart:
    if empty_callback.search(dart.read_text(encoding='utf-8')):
        errors.append(f'{dart}: contains an empty user-action callback')

required_files = [
    root / 'android/app/src/main/AndroidManifest.xml',
    root / 'ios/Runner/Info.plist',
    root / 'web/index.html',
    root / 'Dockerfile',
    root / 'pubspec.yaml',
]
for file in required_files:
    if not file.exists():
        errors.append(f'Missing required project file: {file.relative_to(root)}')

if errors:
    print('\n'.join(errors))
    raise SystemExit(1)

print(f'Validated {len(all_dart)} Dart files, {len(used_keys)} localization keys and required platform files.')
