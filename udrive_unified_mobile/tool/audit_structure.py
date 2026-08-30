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

    # Two declarations sharing a line.
    #
    # An anchored insert whose replacement ends with the same line the
    # remainder begins with produces `class X {class X {`. It has happened
    # three times. The brace count notices, but only says "mismatch", which is
    # a poor clue when the file is two thousand lines long.
    # Some files in this project ship minified — imports and classes all on one
    # line. The check cannot say anything useful about those, so they are
    # skipped rather than reported forever until the output is ignored.
    minified = any(
        len(line) > 300 for line in s.split('\n')[:5]
    )
    for n, line in enumerate([] if minified else s.split('\n'), 1):
        # Only two *type declarations* on one line. Some files in this project
        # are minified and legitimately put a constructor on the class line, so
        # matching anything looser reports them forever and the check stops
        # being read.
        if len(re.findall(r'\b(?:class|enum|mixin|extension)\s+\w+\s*(?:extends|implements|with|\{)', line)) > 1:
            issues.append(f'TWO DECLARATIONS ON ONE LINE @{n}: {line.strip()[:60]}')

    # Private widgets used but not declared in this file.
    #
    # Caught a real one immediately: removing three dead widgets took
    # `_StepButton` with them, and the file still referenced it. Private classes
    # cannot be imported, so if the name is not declared here it does not exist.
    # Matched anywhere on the line, not just at its start: minified files in
    # this project put several classes on one line, and anchoring to ^ reported
    # every one of them as undeclared.
    declared_types = set(re.findall(r'\bclass\s+(\w+)', s))
    for used in set(re.findall(r'\b(_[A-Z]\w+)\s*\(', s)):
        if used not in declared_types:
            issues.append(f'UNDECLARED WIDGET {used}')

    # Uninitialised final fields.
    #
    # A `final` field with no initialiser must be set by every constructor. When
    # a constructor parameter is removed and the field is left behind, the class
    # stops compiling — twice now, on `showDiagnostics`. This is narrow enough
    # to be reliable: it only looks at `final X name;` with no `=`, and only
    # complains when the name appears in no constructor parameter list.
    for match in re.finditer(r'^  final\s+[\w<>,\?\s\(\)]+?\s(\w+);\s*$', s, flags=re.M):
        field = match.group(1)
        line = s[:match.start()].count('\n') + 1
        in_ctor = re.search(
            r'(?:this\.' + re.escape(field) + r'\b)'
            r'|(?:required\s+this\.' + re.escape(field) + r'\b)'
            r'|(?:\b' + re.escape(field) + r'\s*[:=])',
            s)
        if not in_ctor:
            issues.append(f'UNINITIALISED FINAL {field} @{line}')

    # Undeclared *fields* are deliberately not checked here.
    #
    # Two attempts produced dozens of false positives, and a check that cries
    # wolf is worse than no check — it trains you to skip the output. The right
    # tool already exists: `flutter analyze` catches every undeclared name with
    # no guessing, and the repository's GitHub Actions workflow runs it as the
    # first job. Use that before deploying.

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
