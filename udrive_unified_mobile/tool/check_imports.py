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
# `import 'x.dart' hide Foo;` removes Foo from that file's view, which is how
# this codebase already resolves several legacy name clashes. Ignoring `hide`
# would report those as ambiguous forever, and a check that cries wolf gets
# switched off.
HIDDEN = re.compile(r"(?:import|export)\s+'([^']+)'[^;]*?\bhide\s+([\w\s,]+)")

def hidden_names(path, source):
    names = set()
    for match in HIDDEN.finditer(source):
        names |= {n.strip() for n in match.group(2).split(',') if n.strip()}
    return names

def resolve(p, spec):
    if spec.startswith('package:udrive_mobile/'):
        return os.path.join('lib', spec.split('/',1)[1])
    if spec.startswith('package:') or spec.startswith('dart:'):
        return None
    return os.path.normpath(os.path.join(os.path.dirname(p), spec))

EXPORT=re.compile(r"export\s+'([^']+)'")

def reachable(root):
    """Every file whose declarations `root` can see.

    Its own imports and exports, then — from each of those — only their
    *exports*. An import is not transitive in Dart: a file importing B does not
    inherit what B imports. Following imports transitively made this check
    report clashes that the language never sees, which is how a check earns
    being ignored.
    """
    src = files.get(root)
    if src is None: return {root}

    seen = {root}
    frontier = []
    for m in IMPORT.finditer(src):
        t = resolve(root, m.group(1))
        if t and t in files: frontier.append(t)

    while frontier:
        current = frontier.pop()
        if current in seen: continue
        seen.add(current)
        body = files.get(current)
        if body is None: continue
        for m in EXPORT.finditer(body):
            t = resolve(current, m.group(1))
            if t and t in files: frontier.append(t)
    return seen

USE=re.compile(r'\b([A-Z][A-Za-z0-9_]*)\b')
# Files nothing imports are never compiled, so a hit inside one says nothing
# about the build. Reported separately as dead code rather than mixed in with
# real missing imports — `profile_screen.dart` and `driver_profile_screen.dart`
# are both orphaned today and would otherwise produce permanent noise.
imported = set()
for _src in files.values():
    for _m in IMPORT.finditer(_src):
        pass
for _path, _src in files.items():
    for _m in IMPORT.finditer(_src):
        _t = resolve(_path, _m.group(1))
        if _t and _t in files:
            imported.add(_t)
orphans = sorted(
    path for path in files
    if path not in imported and not path.endswith('lib/main.dart'))

bad=0
for p,src in sorted(files.items()):
    if p in orphans: continue
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
for path in orphans:
    print(f'{path}: nothing imports this file — it is never compiled')
print('ORPHANED FILES:', len(orphans))


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


# ------------------------------------------------------- duplicate top levels
#
# A third check, added after a build broke on `DriverDocumentsScreen` being
# declared in both `driver_pages.dart` (a mock) and `driver_documents_screen.dart`
# (the real one). Two public classes with the same name in one package is an
# ambiguous import the moment a file imports both, and dart2js says so only
# after twenty seconds.
#
# Private names (leading underscore) are excluded: they are file-local by
# definition, and this codebase reuses `_Row`, `_Tag` and similar freely.

# Only reported where it actually bites. This codebase has eighteen names
# declared in two files each, and they are harmless as long as no single file
# can see both — a legacy mock model and its replacement living in separate
# corners breaks nothing. Listing all eighteen every run would train everyone
# to ignore the output, so a duplicate is flagged only when some file's imports
# reach more than one declaration of it.
duplicates = 0
for path, source in sorted(files.items()):
    visible_from = reachable(path)
    body = re.sub(r"^(?:import|export)\s+'[^']+'.*$", '', strip(source), flags=re.M)
    for name in sorted(set(USE.findall(body))):
        if name.startswith('_') or name not in owner:
            continue
        if name in hidden_names(path, source):
            continue
        clash = sorted(p2 for p2 in owner[name] if p2 in visible_from)
        if len(clash) < 2:
            continue
        print(f"{path}: '{name}' is ambiguous — declared in "
              f"{', '.join(clash)}")
        duplicates += 1
print('AMBIGUOUS NAMES:', duplicates)
