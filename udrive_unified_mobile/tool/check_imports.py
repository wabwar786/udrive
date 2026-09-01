"""Finds project symbols used in a file that the file never imports.

Written after a build broke on exactly that: `live_trip_navigation_screen.dart`
called `AppControllerScope.of(context)` without importing `app_controller.dart`.
`audit_structure.py` checks shape and brace balance, which that passes cleanly,
and the failure only appeared once dart2js had been running for twenty seconds
in CI.

Deliberately narrow. It only flags a name that is declared somewhere under
`lib/` and is not reachable through this file's imports — so it needs no list of
Flutter or package symbols and produces almost no noise. It does not typecheck
anything, and it is not a substitute for `flutter analyze`; it catches one
common, expensive mistake early.

Run from `udrive_unified_mobile/`:

    python3 tool/check_imports.py
"""

import os, re, sys, collections

ROOT = 'lib'

def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        c=src[i]
        if c=='/' and src[i+1:i+2]=='/':
            while i<n and src[i]!='\n': i+=1
            continue
        if c=='/' and src[i+1:i+2]=='*':
            i+=2
            while i+1<n and src[i:i+2]!='*/': i+=1
            i+=2; continue
        if c in "'\"":
            q=src[i:i+3] if src[i:i+3] in ("'''",'"""') else c
            i+=len(q)
            while i<n and src[i:i+len(q)]!=q:
                if src[i]=='\\': i+=1
                i+=1
            i+=len(q)
            out.append(' ')
            continue
        out.append(c); i+=1
    return ''.join(out)

files={}
for dirpath,_,names in os.walk(ROOT):
    for name in names:
        if name.endswith('.dart'):
            p=os.path.join(dirpath,name)
            files[p]=open(p,encoding='utf-8').read()

DECL=re.compile(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*(?:class|enum|mixin|extension|typedef)\s+([A-Z_]\w*)', re.M)
TOPFN=re.compile(r'^(?:[A-Za-z_][\w<>,\s\?\[\]]*\s+)?([a-z_]\w*)\s*\(', re.M)

declared=collections.defaultdict(set)   # path -> names
owner=collections.defaultdict(set)      # name -> paths
for p,src in files.items():
    s=strip(src)
    for m in DECL.finditer(s):
        declared[p].add(m.group(1)); owner[m.group(1)].add(p)

IMPORT=re.compile(r"(?:import|export)\s+'([^']+)'")
def resolve(p, spec):
    if spec.startswith('package:udrive_mobile/'):
        return os.path.join('lib', spec.split('/',1)[1])
    if spec.startswith('package:') or spec.startswith('dart:'):
        return None
    return os.path.normpath(os.path.join(os.path.dirname(p), spec))

def reachable(p, seen=None):
    if seen is None: seen=set()
    if p in seen: return seen
    seen.add(p)
    src=files.get(p)
    if src is None: return seen
    for m in IMPORT.finditer(src):
        t=resolve(p, m.group(1))
        if t and t in files: reachable(t, seen)
    return seen

USE=re.compile(r'\b([A-Z][A-Za-z0-9_]*)\b')
bad=0
for p,src in sorted(files.items()):
    s=strip(src)
    body=re.sub(r"^(?:import|export)\s+'[^']+'.*$", '', s, flags=re.M)
    vis=set()
    for f in reachable(p):
        vis |= declared[f]
    for name in set(USE.findall(body)):
        if name in vis: continue
        if name not in owner: continue          # not a project symbol
        if p in owner[name]: continue
        print(f"{p}: uses '{name}' (declared in {sorted(owner[name])[0]}) but does not import it")
        bad+=1
print('MISSING IMPORTS:', bad)


# ---------------------------------------------------------------- awaits
#
# A second, narrower check, added after a build broke on `repository.cached()`
# used without `await` — the value was a Future, `.isNotEmpty` does not exist on
# one, and dart2js only said so after twenty seconds in CI.
#
# Only project methods are considered, and only call sites that immediately
# consume the result (`x.foo().bar`, `= x.foo()`, `if (x.foo())`). Anything
# preceded by `await`, `unawaited`, `return`, or followed by `.then` is fine, as
# is a bare statement call. That keeps the noise near zero at the cost of
# missing cases a real analyzer would catch.

# The type argument can itself be generic — `Future<Map<String, String>>` —
# so one level of nesting has to be allowed. Missing that was why this check
# passed over the very call it was written for.
ASYNC_DECL = re.compile(
    r'\bFuture<(?:[^<>]|<[^<>]*>)*>\s+([a-z_]\w*)\s*\(', re.M)
async_names = set()
for _src in files.values():
    async_names |= set(ASYNC_DECL.findall(strip(_src)))

# Names that are also common sync methods elsewhere would produce false hits.
async_names -= {'build', 'toString', 'call'}

missing_await = 0
for path, source in sorted(files.items()):
    body = strip(source)
    for name in async_names:
        patterns = [
            # `x.foo().bar` — the result is used as a value immediately.
            r'\w+\.' + re.escape(name) + r'\(\)\s*\.',
            # `final y = x.foo();` — bound to a local that is then used as if
            # it were the resolved value. This is the shape that broke the
            # build: `final cached = repository.cached();`
            r'(?:final|var)\s+\w+\s*=\s*\w+\.' + re.escape(name) + r'\(',
        ]
        for pattern in patterns:
            for match in re.finditer(pattern, body):
                window = body[max(0, match.start() - 12):match.end()]
                if 'await' in window or 'unawaited' in window:
                    continue
                if body[match.end():match.end() + 5].lstrip().startswith('then'):
                    continue
                line = body[:match.start()].count('\n') + 1
                print(f"{path}:{line}: '{match.group(0).strip()}' "
                      'used without await')
                missing_await += 1
print('MISSING AWAITS:', missing_await)
