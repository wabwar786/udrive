"""Check converted screens against the design system, without a Dart compiler.

There is no Dart or Flutter SDK in this environment, so nothing here is a
substitute for `flutter analyze`. What it does catch is the specific class of
mistake a conversion makes: a named argument a widget does not have, a token
that does not exist, an import left behind, type below the system's floor, and
v1 widgets that were missed.

Usage
-----
    python3 tool/check_design_system.py $(find lib -name '*.dart')

Run it from the repository's `udrive_unified_mobile` folder.
"""

import os
import re
import sys

# The app's lib/, found from this file's own location: tool/ sits beside it.
LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib')

V1 = {
    'PremiumCard': 'UdCard', 'StatusPill': 'UdBadge', 'SectionHeader': 'UdSectionHeader',
    'TextFormField': 'UdTextField', 'ChoiceChip': 'UdChip',
    'CheckboxListTile': 'UdCheckboxRow', 'SwitchListTile': 'UdListRow + UdSwitch',
    'RadioListTile': 'UdRadio', 'AlertDialog': 'showUdDialog',
    'ElevatedButton': 'UdButton', 'OutlinedButton': 'UdButton.outline',
    'FilledButton': 'UdButton.primary', 'FloatingActionButton': 'UdButton',
    'showModalBottomSheet': 'showUdSheet', 'TextButton': 'UdButton.ghost',
    'TextField': 'UdTextField',
}

# The design system's own files. They define the v2 primitives, so of course
# they contain the Material widgets underneath — ud_scaffold.dart IS
# showUdSheet, and app_theme.dart IS the button theme.
SYSTEM = {
    'app_theme.dart', 'app_tokens.dart', 'app_type.dart',
    'ud_button.dart', 'ud_input.dart', 'ud_surface.dart', 'ud_bits.dart',
    'ud_scaffold.dart', 'ud_nav.dart', 'ud_kit.dart',
}

# Deliberate exceptions, each with the reason. A file listed here is not flagged
# for that token; everything else still is.
ALLOWED = {
    ('customer_sos_sheet.dart', 'showModalBottomSheet'):
        'documented in the file: showUdSheet cannot host this layout',
    ('driver_documents_screen.dart', 'AppBar'):
        'full-screen image viewer on navy, shipped deliberately in Phase 17',

    # Raw TextFields that are right as they are. UdTextField draws a label and
    # a field box, which is wrong for a search bar, a chat composer, and an
    # input that is not meant to be seen at all.
    ('otp_screen.dart', 'TextField'):
        'offstage real input, so autofill and paste work',
    ('trip_chat_screen.dart', 'TextField'):
        'chat composer: a field box would be wrong in a message bar',
    ('place_search_screen.dart', 'TextField'):
        'search bar',
    ('customer_home_screen.dart', 'TextField'):
        'search bars on the home map',
    ('udrive_route_flow_screen.dart', 'TextField'):
        'place search bar; the fare field is a UdTextField',
    ('near_me_screen.dart', 'TextField'):
        'search bar',
    ('live_explore_screen.dart', 'TextField'):
        'search bar',
    ('route_fields.dart', 'TextField'):
        'borderless input inside the route box, which already draws the chrome',
    ('tour_map_screen.dart', 'TextField'):
        'the 30px amount entry beside a PKR prefix, deliberately borderless',
    ('hotel_list_screen.dart', 'TextField'):
        'search bar',
}


def strip(src):
    """Remove comments and string bodies, keeping interpolation holes."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            out.append(' ')
            continue
        if src[i] in '\'"':
            quote = src[i]
            triple = src.startswith(quote * 3, i)
            j = i + (3 if triple else 1)
            buf = []
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if triple and src.startswith(quote * 3, j):
                    j += 3
                    break
                if not triple and src[j] == quote:
                    j += 1
                    break
                # Keep ${...} so calls inside interpolation are still checked.
                if src.startswith('${', j):
                    depth, k = 1, j + 2
                    while k < n and depth:
                        if src[k] == '{':
                            depth += 1
                        elif src[k] == '}':
                            depth -= 1
                        k += 1
                    buf.append(' ' + src[j + 2:k - 1] + ' ')
                    j = k
                    continue
                j += 1
            out.append('""' + ''.join(buf))
            i = j
            continue
        out.append(src[i])
        i += 1
    return ''.join(out)


def constructors():
    """Every Ud* widget's named parameters, read from core/widgets."""
    found = {}
    for base, _, names in os.walk(os.path.join(LIB, 'core', 'widgets')):
        for name in names:
            if not name.endswith('.dart'):
                continue
            src = open(os.path.join(base, name), encoding='utf-8').read()
            # Named constructors: `const UdButton.primary({...}) : variant = ...`
            # The parameter list holds braces, so it is matched by scanning
            # rather than by a regex.
            for m in re.finditer(r'(?:const|factory)\s+(Ud[A-Z]\w*)\.(\w+)\s*\(', src):
                depth, i, n = 1, m.end(), len(src)
                while i < n and depth:
                    if src[i] == '(':
                        depth += 1
                    elif src[i] == ')':
                        depth -= 1
                    i += 1
                params = src[m.end():i - 1]
                key = f'{m.group(1)}.{m.group(2)}'
                fields = set(re.findall(r'(?:this\.|required\s+this\.)(\w+)', params))
                fields |= set(re.findall(r'(?:required\s+)?[\w<>,?\[\] ]+\s+(\w+)\s*[,}=]', params))
                fields.add('key')
                found.setdefault(key, set()).update(fields)
            for m in re.finditer(
                    r'class\s+(Ud\w+)\b.*?\n\s*const\s+\1(?:\.(\w+))?\s*\((.*?)\)\s*(?::|;|\{)',
                    src, re.S):
                cls, named_ctor, params = m.group(1), m.group(2), m.group(3)
                key = f'{cls}.{named_ctor}' if named_ctor else cls
                fields = set(re.findall(r'(?:this\.|required\s+this\.)(\w+)', params))
                fields |= set(re.findall(r'required\s+[\w<>,?\[\] ]+\s+(\w+)\s*[,}\)]', params))
                fields.add('key')
                found[key] = fields
    return found


def tokens():
    """Every member of the theme classes."""
    found = {}
    for name in ('app_tokens.dart', 'app_theme.dart', 'app_type.dart'):
        src = open(os.path.join(LIB, 'core', 'theme', name), encoding='utf-8').read()
        for m in re.finditer(r'class\s+(\w+)\s*\{(.*?)\n\}', src, re.S):
            cls, body = m.group(1), m.group(2)
            members = set(re.findall(r'static\s+const\s+(?:[\w<>?]+\s+)?(\w+)\s*=', body))
            members |= set(re.findall(r'static\s+(?:[\w<>?]+)\s+(\w+)\s*\(', body))
            found.setdefault(cls, set()).update(members)
    return found


def check(path, ctors, toks):
    raw = open(path, encoding='utf-8').read()
    src = strip(raw)
    name = os.path.basename(path)
    problems = []

    for open_c, close_c, label in (('(', ')', 'paren'), ('{', '}', 'brace'), ('[', ']', 'bracket')):
        depth = low = 0
        for ch in src:
            if ch == open_c:
                depth += 1
            elif ch == close_c:
                depth -= 1
                low = min(low, depth)
        if depth or low < 0:
            problems.append(f'{label} balance: end={depth} min={low}')

    for token, replacement in V1.items():
        if (name, token) in ALLOWED or name in SYSTEM:
            continue
        hits = len(re.findall(r'(?<![A-Za-z0-9_.])' + token + r'(?![A-Za-z0-9_])', src))
        if hits:
            problems.append(f'v1 {token} x{hits} -> {replacement}')

    small = sorted({float(s) for s in re.findall(r'fontSize:\s*([0-9.]+)', src) if float(s) < 12.5})
    if small:
        problems.append(f'type below the 12.5 floor: {small}')

    # Named arguments against each Ud* constructor.
    for m in re.finditer(r'(?<![A-Za-z0-9_])(Ud[A-Z]\w*(?:\.\w+)?)\s*\(', src):
        call = m.group(1)
        if call not in ctors:
            base = call.split('.')[0]
            if base in ctors:
                problems.append(f'{call}: no such named constructor')
            continue
        depth, i, n = 1, m.end(), len(src)
        while i < n and depth:
            if src[i] == '(':
                depth += 1
            elif src[i] == ')':
                depth -= 1
            i += 1
        body = src[m.end():i - 1]
        # Only top-level `name:` pairs belong to this call.
        level, args, buf = 0, [], []
        for ch in body:
            if ch in '([{':
                level += 1
            elif ch in ')]}':
                level -= 1
            if ch == ',' and level == 0:
                args.append(''.join(buf))
                buf = []
            else:
                buf.append(ch)
        args.append(''.join(buf))
        for arg in args:
            label = re.match(r'\s*(\w+)\s*:', arg)
            if label and label.group(1) not in ctors[call]:
                problems.append(f'{call}: no parameter "{label.group(1)}"')

    for m in re.finditer(r'(?<![A-Za-z0-9_])(AppColors|AppType|AppTint|AppText|AppRadii|'
                         r'AppShadows|AppSpacing|AppSizes|AppMap|AppStatus)\.(\w+)', src):
        cls, member = m.group(1), m.group(2)
        if member.startswith('_'):
            continue
        if cls in toks and member not in toks[cls]:
            problems.append(f'{cls}.{member}: no such token')

    exported_here = set(re.findall(r"""export\s+'([^']+)'""", raw))
    for m in re.finditer(r"""import\s+'([^']+)'\s*(?:as\s+(\w+)\s*)?;""", raw):
        target, alias = m.group(1), m.group(2)
        if alias or target.startswith('dart:'):
            continue
        # A file that re-exports what it imports is handing the names on, not
        # using them. app_tokens.dart does exactly this for app_type.dart, and
        # sixty-three screens depend on it.
        if target in exported_here:
            continue
        stem = os.path.basename(target).replace('.dart', '')
        resolved = target
        if not target.startswith('package:'):
            # The file under test may sit in a staging tree whose siblings do
            # not exist. Resolve against its position inside the real lib/.
            here = os.path.dirname(path)
            marker = f'{os.sep}lib{os.sep}'
            if marker in path:
                here = os.path.join(LIB, os.path.dirname(path.split(marker, 1)[1]))
            resolved = os.path.normpath(os.path.join(here, target))
        if not os.path.exists(resolved) and not target.startswith('package:'):
            problems.append(f'import not found: {target}')
            continue
        if target.startswith('package:flutter/') or target.startswith('package:'):
            continue
        # The imported file itself, plus anything it re-exports. The export
        # targets are relative to IT, not to us; the file itself is already a
        # full path and must not be joined again.
        reexports = re.findall(r"""export\s+'([^']+)'""",
                               open(resolved, encoding='utf-8').read())
        sources = [resolved] + [
            os.path.normpath(os.path.join(os.path.dirname(resolved), r))
            for r in reexports]
        exported = set()
        for f in sources:
            if os.path.exists(f):
                text = open(f, encoding='utf-8').read()
                exported |= set(re.findall(r'^(?:abstract\s+)?(?:sealed\s+)?(?:final\s+)?'
                                           r'(?:class|enum|mixin|extension|typedef)\s+(\w+)',
                                           text, re.M))
                exported |= set(re.findall(r'^(?:[\w<>?,\[\] ]+)\s+(\w+)\s*[(<]', text, re.M))
                exported |= set(re.findall(r'^const\s+(\w+)', text, re.M))
        if exported and not any(
                re.search(r'(?<![A-Za-z0-9_])' + re.escape(n) + r'(?![A-Za-z0-9_])', src)
                for n in exported):
            problems.append(f'import possibly unused: {target} ({stem})')

    return problems


def main():
    ctors, toks = constructors(), tokens()
    print(f'{len(ctors)} Ud* constructors, '
          f'{sum(len(v) for v in toks.values())} theme tokens\n')
    total = 0
    for path in sys.argv[1:]:
        problems = check(path, ctors, toks)
        total += len(problems)
        mark = 'CLEAN' if not problems else f'{len(problems)} problem(s)'
        print(f'{os.path.basename(path):42} {mark}')
        for p in problems:
            print(f'     - {p}')
    print(f'\n{total} problem(s) in {len(sys.argv) - 1} file(s)')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
