"""Semantic diff of two Hermes config.yaml files (stdlib only, YAML subset Hermes writes).
   python profile-diff.py A.yaml B.yaml [--show-noise]
Prints paths only in A, only in B, and different values. Comments are ignored."""
import re, sys

NOISE = ('providers.nvidia-nim.models.', 'known_builtin_toolsets', 'known_plugin_toolsets', '_config_version')


def strip_comment(s):
    out, q = [], None
    for i, ch in enumerate(s):
        if q:
            if ch == q:
                q = None
        elif ch in '"\'':
            q = ch
        elif ch == '#' and (i == 0 or s[i - 1] in ' \t'):
            break
        out.append(ch)
    return ''.join(out).rstrip()


def scalar(v):
    v = v.strip()
    if v in ('', '~', 'null'):
        return ''
    if v == '{}':
        return {}
    if v == '[]':
        return []
    if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
        return v[1:-1]
    if v.startswith('[') and v.endswith(']'):
        return [scalar(x) for x in v[1:-1].split(',') if x.strip()]
    return v


def load(path):
    rows = []
    for raw in open(path, encoding='utf-8-sig', errors='replace').read().splitlines():
        s = strip_comment(raw)
        if not s.strip():
            continue
        rows.append((len(s) - len(s.lstrip(' ')), s.strip()))
    pos = [0]

    def parse(indent):
        if pos[0] >= len(rows):
            return ''
        if rows[pos[0]][1].startswith('- ') or rows[pos[0]][1] == '-':
            return parse_list(rows[pos[0]][0])
        return parse_map(indent)

    def parse_map(indent):
        d = {}
        while pos[0] < len(rows):
            ind, s = rows[pos[0]]
            if ind < indent or s.startswith('- '):
                break
            m = re.match(r'^(.*?):(?:\s+(.*))?$', s)
            if not m:
                pos[0] += 1
                continue
            key, val = m.group(1).strip().strip('"\''), m.group(2)
            pos[0] += 1
            if val is None or val == '':
                if pos[0] < len(rows) and (rows[pos[0]][0] > ind or (rows[pos[0]][0] == ind and rows[pos[0]][1].startswith('- '))):
                    d[key] = parse(rows[pos[0]][0])
                else:
                    d[key] = ''
            elif val in ('|', '>', '|-', '>-'):
                buf = []
                while pos[0] < len(rows) and rows[pos[0]][0] > ind:
                    buf.append(rows[pos[0]][1]); pos[0] += 1
                d[key] = ' '.join(buf)
            else:
                d[key] = scalar(val)
        return d

    def parse_list(indent):
        items = []
        while pos[0] < len(rows):
            ind, s = rows[pos[0]]
            if ind != indent or not (s.startswith('- ') or s == '-'):
                break
            rest = s[1:].strip()
            if not rest:
                pos[0] += 1
                items.append(parse(rows[pos[0]][0]) if pos[0] < len(rows) else '')
            elif re.match(r'^[^\s:][^:]*:(\s|$)', rest) and not rest.startswith(('"', "'")):
                rows[pos[0]] = (indent + 2, rest)
                items.append(parse_map(indent + 2))
            else:
                pos[0] += 1
                items.append(scalar(rest))
        return items

    return parse(0)


def flat(o, p=''):
    out = {}
    if isinstance(o, dict):
        if not o and p:
            out[p] = '{}'
        for k, v in o.items():
            out.update(flat(v, f'{p}.{k}' if p else k))
    elif isinstance(o, list):
        if o and all(not isinstance(x, (dict, list)) for x in o):
            out[p] = ', '.join(str(x) for x in o)
        elif not o:
            out[p] = '[]'
        else:
            for i, v in enumerate(o):
                out.update(flat(v, f'{p}[{i}]'))
    else:
        out[p] = str(o)
    return out


if __name__ == '__main__':
    a, b = flat(load(sys.argv[1])), flat(load(sys.argv[2]))
    show_noise = '--show-noise' in sys.argv
    prefixes = ()
    if '--prefix' in sys.argv:
        prefixes = tuple(x for x in sys.argv[sys.argv.index('--prefix') + 1].split(',') if x)
    keep = lambda k: (show_noise or not k.startswith(NOISE)) and (not prefixes or k.startswith(prefixes))
    only_a = sorted(k for k in a if k not in b and keep(k))
    only_b = sorted(k for k in b if k not in a and keep(k))
    diff = sorted(k for k in a if k in b and a[k] != b[k] and keep(k))
    cut = lambda v: (v[:90] + '...') if len(v) > 90 else v
    print(f'ONLY IN A ({len(only_a)}):')
    for k in only_a: print(f'  {k} = {cut(a[k])}')
    print(f'ONLY IN B ({len(only_b)}):')
    for k in only_b: print(f'  {k} = {cut(b[k])}')
    print(f'DIFFERENT ({len(diff)}):')
    for k in diff: print(f'  {k}\n     A: {cut(a[k])}\n     B: {cut(b[k])}')
