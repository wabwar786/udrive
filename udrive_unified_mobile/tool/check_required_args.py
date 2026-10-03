"""Two compile errors the repo's own tools do not catch.

Written after a Railway build failed on exactly these, with nothing in `tool/`
having flagged either:

  1. A constructor invoked without one of its `required` named parameters —
     `const DriverFoundingScreen()` against
     `const DriverFoundingScreen({required this.founding, super.key})`.

  2. A private helper called from a class that does not own it —
     `_number(json['x'])` inside `RentalVehicle.fromJson` while `_number` was a
     `static` on `RentalRepository`. Dart will not resolve another class's
     private static unqualified.

Both checks are brace-aware: a class body is found by matching braces, not by
guessing a window, because a guessed window attributes one class's constructor
to the class above it and the output becomes noise nobody reads.

Where it cannot be sure it says nothing. The second check only fires when a
private name has exactly one declaration in the whole file — with two, the call
may legitimately resolve to the caller's own copy, and a warning would be wrong.
"""

import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else 'lib'

DART = sorted(
    os.path.join(r, f)
    for r, _, fs in os.walk(ROOT)
    for f in fs
    if f.endswith('.dart')
)

# Named parameters every widget takes and nobody passes by hand.
IGNORED_PARAMS = {'key', 'super'}


def strip(text):
    """Blank out comments and string bodies, keeping every character position."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == '//':
            while i < n and text[i] != '\n':
                out[i] = ' '
                i += 1
        elif two == '/*':
            while i < n and text[i:i + 2] != '*/':
                if text[i] != '\n':
                    out[i] = ' '
                i += 1
            for j in range(i, min(i + 2, n)):
                out[j] = ' '
            i += 2
        elif text[i] in '\'"':
            quote = text[i]
            triple = text[i:i + 3] == quote * 3
            end = quote * 3 if triple else quote
            i += len(end)
            while i < n and text[i:i + len(end)] != end:
                if text[i] == '\\':
                    out[i] = ' '
                    i += 1
                if i < n and text[i] != '\n':
                    out[i] = ' '
                i += 1
            i += len(end)
        else:
            i += 1
    return ''.join(out)


def match_bracket(text, start):
    """Index of the bracket closing the one at `start`, or None."""
    pairs = {'(': ')', '{': '}', '[': ']'}
    if start >= len(text) or text[start] not in pairs:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] in pairs:
            depth += 1
        elif text[i] in ')}]':
            depth -= 1
            if depth == 0:
                return i
    return None


def class_bodies(body):
    """(name, start_of_body, end_of_body) for every class in the file."""
    out = []
    for m in re.finditer(r'\bclass\s+(\w+)', body):
        brace = body.find('{', m.end())
        if brace == -1:
            continue
        end = match_bracket(body, brace)
        if end is None:
            continue
        out.append((m.group(1), brace, end))
    return out


def line_of(body, pos):
    return body[:pos].count('\n') + 1


missing_args = []
cross_class = []

# ───────────────────────── gather required parameters, class by class

required = {}
declared_in = {}

for path in DART:
    body = strip(open(path, encoding='utf-8').read())
    for name, start, end in class_bodies(body):
        inner = body[start:end]
        # The constructor as written inside its own class body.
        ctor = re.search(
            r'(?:^|[;{}\s])(?:const\s+)?' + re.escape(name) + r'\s*\(',
            inner,
        )
        if not ctor:
            continue
        open_paren = start + ctor.end() - 1
        close = match_bracket(body, open_paren)
        if close is None:
            continue
        args = body[open_paren + 1:close]
        names = set()
        # The type, if written, cannot contain a comma — without that bound the
        # match ran across parameter boundaries and paired `required` with a
        # later, optional parameter's name. That produced six hundred
        # confident, wrong warnings, which is worse than no checker at all.
        for p in re.finditer(
            r'required\s+(?:[\w<>?.]+(?:<[^<>]*>)?\s+)?(?:this\.)?(\w+)\s*[,}=)]',
            args,
        ):
            if p.group(1) not in IGNORED_PARAMS:
                names.add(p.group(1))
        if names:
            # A private class is file-local, so two files may each hold their
            # own `_Fact` with different parameters. Keyed globally they
            # collided and every file was checked against another file's
            # widget. Public names stay global; private ones are keyed by file.
            key = (path, name) if name.startswith('_') else (None, name)
            required[key] = names
            declared_in[key] = path

# ───────────────────────── check every call site

for path in DART:
    body = strip(open(path, encoding='utf-8').read())
    bodies = class_bodies(body)

    for (scope, name), names in required.items():
        if scope is not None and scope != path:
            continue
        for m in re.finditer(r'(?<![\w.$])' + re.escape(name) + r'\s*\(', body):
            before = body[:m.start()].rstrip()
            # The declaration itself, a factory, or a type position.
            if before.endswith('class') or before.endswith('factory'):
                continue
            # Inside the class's own body at the constructor position.
            inside_own = any(
                n == name and s < m.start() < e for n, s, e in bodies
            )
            if inside_own and re.search(
                r'(?:const\s+)?$', body[max(0, m.start() - 10):m.start()]
            ) and body[:m.start()].rstrip().endswith(('{', '}', ';')):
                continue
            close = match_bracket(body, m.end() - 1)
            if close is None:
                continue
            args = body[m.end():close]
            # A declaration, not a call: only a parameter list opens with `{`
            # (the named-parameter block). Without this the checker flagged
            # every constructor against itself.
            if args.lstrip().startswith('{'):
                continue
            given = set(re.findall(r'(?:^|,)\s*(\w+)\s*:', args))
            miss = names - given
            if miss:
                missing_args.append(
                    f'{path}:{line_of(body, m.start())}: {name}(...) missing '
                    f'required {", ".join(sorted(miss))}'
                    f'  [declared in {declared_in[(scope, name)]}]'
                )

# ───────────────────────── private statics used outside their class

for path in DART:
    body = strip(open(path, encoding='utf-8').read())
    bodies = class_bodies(body)

    def owner_of(pos):
        for n, s, e in bodies:
            if s < pos < e:
                return n
        return None

    # Every declaration of a private callable, with its owner.
    declarations = {}
    for m in re.finditer(r'(?:^|[;{}])\s*([\w<>?,.\s]*?)\b(_\w+)\s*\(', body):
        prefix, fname = m.group(1), m.group(2)
        if 'return' in prefix or '=' in prefix:
            continue
        pos = m.start(2)
        declarations.setdefault(fname, []).append(
            (owner_of(pos), 'static' in prefix)
        )

    for fname, decls in declarations.items():
        # Only when there is exactly one, and it is a static inside a class.
        if len(decls) != 1:
            continue
        own, is_static = decls[0]
        if own is None or not is_static:
            continue
        for m in re.finditer(r'(?<![\w.$])' + re.escape(fname) + r'\s*\(', body):
            where = owner_of(m.start())
            if where is not None and where != own:
                cross_class.append(
                    f'{path}:{line_of(body, m.start())}: {fname}(...) called in '
                    f'{where}, but it is a private static on {own}'
                )

for p in missing_args:
    print(p)
for c in cross_class:
    print(c)
print(f'MISSING REQUIRED ARGUMENTS: {len(missing_args)}')
print(f'PRIVATE STATIC USED OUTSIDE ITS CLASS: {len(cross_class)}')
sys.exit(1 if missing_args or cross_class else 0)
