"""Finds `const` expressions that reach a runtime colour token.

`AppColors.secondary`, `AppColors.accent`, `AppTint.brand` and `AppText.onBrand`
follow the accent the customer picks, so they are runtime getters. Dart rejects
them inside any `const` expression.

The first version of this check looked one line at a time, which is not how
`const` works: an outer `const TextStyle(` four lines up makes everything inside
it constant too. That version passed clean and the build failed on sixty-odd
sites — so this one walks the balanced bracket group each `const` opens and
checks the whole body.

Run from udrive_unified_mobile/:

    python3 tool/check_const_colours.py
"""

import os
import re
import sys

TOKENS = (
    'AppColors.secondary',
    'AppColors.accent',
    'AppTint.brand',
    'AppText.onBrand',
)

CLOSERS = {'(': ')', '[': ']', '{': '}'}


def group_end(src: str, i: int) -> int:
    """Index just past the balanced group whose opening bracket is at `i`."""
    stack = [CLOSERS[src[i]]]
    i += 1
    while i < len(src) and stack:
        ch = src[i]
        if ch in ("'", '"'):
            quote = ch
            i += 1
            while i < len(src) and src[i] != quote:
                if src[i] == '\\':
                    i += 1
                i += 1
        elif ch in CLOSERS:
            stack.append(CLOSERS[ch])
        elif ch == stack[-1]:
            stack.pop()
        i += 1
    return i


def governed_text(src: str, after_keyword: int):
    """What a `const` at this position makes constant, or None."""
    i = after_keyword
    while i < len(src) and src[i].isspace():
        i += 1
    if i >= len(src):
        return None

    if src[i] in CLOSERS:
        return src[i:group_end(src, i)]

    match = re.match(r'[A-Za-z_][\w.]*(?:<[^>]*>)?', src[i:])
    if not match:
        return None

    j = i + match.end()
    while j < len(src) and src[j].isspace():
        j += 1

    if j < len(src) and src[j] == '(':
        return src[i:group_end(src, j)]
    if j < len(src) and src[j] == '=':
        stop = src.find(';', j)
        return src[i:stop if stop > 0 else len(src)]
    return None


problems = 0
for root, _, names in os.walk('lib'):
    for name in sorted(names):
        if not name.endswith('.dart'):
            continue
        path = os.path.join(root, name)
        src = open(path).read()
        if not any(token in src for token in TOKENS):
            continue

        for match in re.finditer(r'\bconst\b', src):
            body = governed_text(src, match.end())
            if body is None:
                continue
            found = [token for token in TOKENS if token in body]
            if not found:
                continue
            line = src[:match.start()].count('\n') + 1
            print(f'{path}:{line}: const expression contains {found[0]}, '
                  'which is a runtime getter')
            problems += 1

# ------------------------------------------------- const constructor mismatch
#
# Removing `const` from an expression is safe. Removing it from a *constructor
# declaration* is not, because every `const X(...)` call site then fails — and
# in files written one-class-per-line, a blunt edit hits the declaration without
# meaning to. That is exactly how `DriverReviewsScreen` broke.

declared: dict[str, bool] = {}
for root, _, names in os.walk('lib'):
    for name in names:
        if not name.endswith('.dart'):
            continue
        src = open(os.path.join(root, name)).read()
        for match in re.finditer(r'class\s+(\w+)\s+extends\s+\w+[^{]*\{', src):
            cls = match.group(1)
            tail = src[match.end():match.end() + 400]
            ctor = re.search(r'(const\s+)?' + re.escape(cls) + r'\s*\(', tail)
            if ctor:
                declared[cls] = ctor.group(1) is not None

invoked: set[str] = set()
for root, _, names in os.walk('lib'):
    for name in names:
        if not name.endswith('.dart'):
            continue
        src = open(os.path.join(root, name)).read()
        invoked |= set(re.findall(r'\bconst\s+([A-Z]\w*)\s*\(', src))

for cls in sorted(invoked):
    if cls in declared and not declared[cls]:
        print(f"'{cls}' is invoked as `const {cls}(` but its constructor is "
              'not declared const')
        problems += 1

# ------------------------------------------------ keyword-less declarations
#
# `const x = …` cannot simply lose its keyword: `x = …` at top level or as a
# class field is not valid Dart. When the const-removal pass ran, two such
# declarations were left bare — `services` in dummy_data.dart and `_bodyMid` in
# service_illustration.dart — and nothing caught it until the compiler did.

for root, _, names in os.walk('lib'):
    for name in sorted(names):
        if not name.endswith('.dart'):
            continue
        path = os.path.join(root, name)
        for number, line in enumerate(open(path).read().split('\n'), 1):
            # Column zero only. Indented assignments are ordinary statements
            # inside methods; a top-level one with no keyword cannot be
            # anything but damage. Widening this to class fields matched a
            # hundred harmless lines, and a check that cries wolf is one people
            # switch off.
            if re.match(r'^[a-z_]\w*\s*=[^=]', line):
                print(f'{path}:{number}: declaration has no `final`, `const`, '
                      f'`var` or type — {line.strip()[:60]}')
                problems += 1

print('CONST RUNTIME COLOURS:', problems)
sys.exit(1 if problems else 0)
