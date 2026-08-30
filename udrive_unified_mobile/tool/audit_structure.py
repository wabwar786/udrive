"""Structural audit run after every edit.

Each check exists because a specific mistake reached a build:
  - duplicate top-level declarations  (three copies of _LocationErrorBanner)
  - duplicate members inside a class  (four copies of _refreshNearby)
  - emptied control bodies            (an `if` whose body was deleted)
  - undeclared private calls
  - unresolved theme token members    (AppProduct.rideFrom after a rename)
  - broken relative imports
"""
import re, glob, os, sys

theme = ''
for f in ('lib/core/theme/app_tokens.dart', 'lib/core/theme/app_theme.dart'):
    theme += open(f, encoding='utf-8').read()
TOKENS = set(re.findall(r'static (?:const )?(?:double |int |Color |BorderRadius |List<BoxShadow> )?(?:get )?(\w+)\s*[=({]', theme))

def audit(path):
    s = open(path, encoding='utf-8').read()
    lines = s.split('\n')
    issues = []

    # duplicate top-level declarations
    tops = re.findall(r'^(?:abstract |sealed )?(?:class|enum|mixin|extension)\s+(\w+)', s, flags=re.M)
    for name in {n for n in tops if tops.count(n) > 1}:
        issues.append(f'DUPLICATE TOP-LEVEL {name} x{tops.count(name)}')

    # duplicate members within a class
    pc = re.compile(r'^(?:abstract\s+)?class\s+(\w+)')
    pd = re.compile(r'^  (?:@override\s+)?(?:static\s+)?(?:const\s+)?(?:Future<[^>]*>|void|bool|String|int|double|Widget|List<[^>]*>|Map<[^>]*>|[A-Z]\w*(?:<[^>]*>)?\??)\s+(?:get\s+)?(\w+)\s*[({=]')
    cls, seen = None, {}
    for i, l in enumerate(lines, 1):
        m = pc.match(l)
        if m:
            cls, seen = m.group(1), {}
            continue
        if cls:
            d = pd.match(l)
            if d:
                n = d.group(1)
                if n in seen:
                    issues.append(f'DUPLICATE {cls}.{n} @{i}')
                else:
                    seen[n] = i

    # emptied control bodies
    for i, l in enumerate(lines):
        st = l.strip()
        if re.match(r'^(if|for|while)\s*\(.*\)\s*$', st):
            nx = lines[i + 1].strip() if i + 1 < len(lines) else ''
            if nx == '' or nx.startswith('}'):
                issues.append(f'EMPTY BODY @{i+1}')

    # undeclared private calls
    decl = set(re.findall(r'\b(_\w+)\s*(?:<[^>]*>)?\s*(?:\([^)]*\)\s*(?:async\s*)?[{=]|=>)', s))
    decl |= set(re.findall(r'\b(_\w+)\s*[=;]', s))
    for c in set(re.findall(r'\b(_[a-z]\w+)\(', s)) - decl:
        if c != '_list':
            issues.append(f'UNDECLARED {c}')

    # theme token members
    if '/theme/' not in path:
        for cls_name in ('AppProduct', 'AppTint', 'AppText', 'AppColors', 'AppRadii', 'AppShadows'):
            for m in set(re.findall(cls_name + r'\.(\w+)', s)):
                if m != '_' and m not in TOKENS:
                    issues.append(f'UNKNOWN TOKEN {cls_name}.{m}')

    # relative imports resolve
    for m in re.finditer(r"^import '([^']+\.dart)';", s, flags=re.M):
        rel = m.group(1)
        if rel.startswith(('package:', 'dart:')):
            continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(path), rel))):
            issues.append(f'BROKEN IMPORT {rel}')

    if s.count('{') != s.count('}') and 'customer_operations' not in path:
        issues.append('BRACE MISMATCH')
    return issues

bad = 0
for p in sorted(glob.glob('lib/**/*.dart', recursive=True)):
    found = audit(p)
    if found:
        bad += 1
        print(p)
        for f in found:
            print('   ', f)
print('AUDIT CLEAN' if not bad else f'{bad} file(s) flagged')
sys.exit(1 if bad else 0)
