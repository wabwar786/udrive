"""Per-method scope check: `x.y` where x is neither a class field, nor a
parameter, nor a local declared in that method.

Catches the Phase 18 break: `final controller = ...` deleted from a build()
while `controller.` reads remained.
"""
import re, sys, glob

def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        if src[i:i+2]=='//':
            while i<n and src[i]!='\n': i+=1
        elif src[i:i+2]=='/*':
            i+=2
            while i+1<n and src[i:i+2]!='*/':
                if src[i]=='\n': out.append('\n')
                i+=1
            i+=2
        elif src[i] in '\'"':
            q=src[i];i+=1;out.append(' ')
            while i<n and src[i]!=q:
                if src[i]=='\\': i+=2; continue
                if src[i]=='\n': out.append('\n')
                if src[i]=='$' and i+1<n and src[i+1]=='{':
                    d=0;j=i+1
                    while j<n:
                        if src[j]=='{': d+=1
                        elif src[j]=='}':
                            d-=1
                            if d==0: break
                        j+=1
                    out.append(src[i+2:j]); i=j+1; continue
                i+=1
            i+=1
        else:
            out.append(src[i]); i+=1
    return ''.join(out)

FREE={'widget','context','mounted','super','this','setState','print','rootBundle',
      'int','double','num','bool','void','dynamic'}

def bal(s,i):
    d=0;j=i
    while j<len(s):
        if s[j]=='{': d+=1
        elif s[j]=='}':
            d-=1
            if d==0: return j
        j+=1
    return len(s)-1

def classes(s):
    for m in re.finditer(r'^(?:abstract\s+)?class\s+(\w+)', s, re.M):
        o=s.find('{', m.end())
        if o<0: continue
        yield m.group(1), o, bal(s,o)

def methods(body):
    """(name, open, close) for every `... name(...) {` and `... name(...) async {`"""
    KW={'for','if','while','switch','catch','do','else','try','return','assert','with'}
    for m in re.finditer(r'(\w+)\s*\(([^;{}()]*(?:\([^()]*\)[^;{}()]*)*)\)\s*(?:async\s*\*?\s*)?\{', body):
        if m.group(1) in KW: continue
        o=body.find('{', m.end()-1)
        yield m.group(1), m.group(2), o, bal(body,o)

hits=[]
for f in sorted(sys.argv[1:] or glob.glob('lib/**/*.dart',recursive=True)):
    raw=open(f).read(); s=strip(raw)
    prefixes=set(re.findall(r'\bimport\s+\S+\s+as\s+(\w+)', raw))
    tops=set(re.findall(r'^\s*(?:const|final)\s+(?:[\w<>,?\[\] ]+\s+)?(\w+)\s*=', s, re.M))
    tops|=set(re.findall(r'^[\w<>,?\[\], ]+\s+(\w+)\s*\(', s, re.M))
    for cls, co, cc in classes(s):
        body=s[co:cc]
        # class fields: declarations at class level (not inside a method body)
        holes=[(o,c) for _,_,o,c in methods(body)]
        def inside(i): return any(o<=i<=c for o,c in holes)
        fields=set()
        for fm in re.finditer(r'\b(?:final|const|late|static|var)\s+(?:[\w<>,?\[\]. ]+\s+)?(\w+)\s*[=;]', body):
            if not inside(fm.start()): fields.add(fm.group(1))
        for fm in re.finditer(r'^\s*[A-Za-z_][\w<>,?\[\]. ]*\s+(\w+)\s*[;=]', body, re.M):
            if not inside(fm.start()): fields.add(fm.group(1))
        fields|=set(re.findall(r'\bthis\.(\w+)', body))
        fields|=set(re.findall(r'\b(?:get|set)\s+(\w+)', body))
        fields|={n for n,_,_,_ in methods(body)}
        for name, params, mo, mc in methods(body):
            mbody=body[mo:mc]
            scope=set(fields)|FREE|prefixes|tops
            scope|=set(re.findall(r'(\w+)\s*[,)]|(\w+)\s*$', params) and
                       [w for w in re.findall(r'(\w+)\s*(?=[,)]|$)', params)])
            scope|=set(re.findall(r'\b(?:final|const|var|late)\s+(?:[\w<>,?\[\]. ]+\s+)?(\w+)\s*[=;]', mbody))
            scope|=set(re.findall(r'^\s*[\w<>,?\[\]. ]+\s+(\w+)\s*=', mbody, re.M))
            scope|=set(re.findall(r'\bfor\s*\(\s*(?:final|var)?\s*(?:[\w<>,?]+\s+)?(\w+)\s+in\b', mbody))
            scope|=set(re.findall(r'\bcatch\s*\(\s*(\w+)(?:\s*,\s*(\w+))?', mbody) and
                       [w for p in re.findall(r'\bcatch\s*\(\s*(\w+)(?:\s*,\s*(\w+))?', mbody) for w in p if w])
            # closure params: (a, b) => / (a) { / (a, b) {
            for cm in re.finditer(r'\(([^()]*)\)\s*(?:async\s*)?(?:=>|\{)', mbody):
                scope|=set(re.findall(r'(\w+)\s*(?=[,)]|$)', cm.group(1)))
            scope|=set(re.findall(r'(\w+)\s*\(', mbody))
            scope|=set(re.findall(r'\b(\w+):', mbody))
            for um in re.finditer(r'(?<![\w.$?!])([a-z_]\w*)\.(?!\.)\s*\w', mbody):
                n=um.group(1)
                if n in scope: continue
                off=co+mo+um.start()
                hits.append((f, s[:off].count('\n')+1, n, cls, name))
seen=set(); out=[]
for h in hits:
    k=(h[0],h[2],h[3],h[4])
    if k in seen: continue
    seen.add(k); out.append(h)
for f,l,n,c,m in out:
    print(f'{f}:{l}  `{n}.` in {c}.{m}()')
print('hits:', len(out))
