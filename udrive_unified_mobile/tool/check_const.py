"""Find `const` widget calls whose arguments are not constant.

Dart requires every argument inside a `const` constructor call to be a constant
expression. `AppType.caption.copyWith(...)` is a method call, so a `const Text`
around it does not compile. A conversion that swaps a literal TextStyle for a
copyWith is exactly how this gets introduced.
"""
import re
import sys

NON_CONST = re.compile(r'\.(copyWith|withValues|withOpacity|format|toString)\s*\(')


def scan(path):
    src = open(path, encoding='utf-8').read()
    bad = []
    for m in re.finditer(r'(?<![A-Za-z0-9_])const\s+([A-Z]\w*(?:\.\w+)?)\s*\(', src):
        depth, i, n = 1, m.end(), len(src)
        while i < n and depth:
            if src[i] == '(':
                depth += 1
            elif src[i] == ')':
                depth -= 1
            i += 1
        body = src[m.end():i - 1]
        # Nested `const` re-opens a constant context, but a non-const call
        # anywhere in this body is still a problem for THIS const.
        hit = NON_CONST.search(body)
        if hit:
            line = src.count('\n', 0, m.start()) + 1
            bad.append((line, m.group(1), body[max(0, hit.start() - 40):hit.end() + 20]
                        .replace('\n', ' ')))
    return bad


total = 0
for path in sys.argv[1:]:
    for line, cls, snippet in scan(path):
        total += 1
        print(f'{path.split("/")[-1]}:{line}  const {cls}(...)  <- {snippet.strip()}')
print(f'{total} const violation(s)')
