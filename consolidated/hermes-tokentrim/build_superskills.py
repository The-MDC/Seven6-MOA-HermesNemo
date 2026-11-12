#!/usr/bin/env python3
"""Fold every skill category of ONE Hermes profile into a single "suite" skill (stdlib only).

Why: Hermes lists every enabled skill in the system prompt of every request (name + <=60 chars). 171 skills
cost ~15k chars (~3.8k tokens) per request. A suite is one skill per category: its SKILL.md is a router (table
of the category's guides with one-line scopes and paths). The original guides are NOT touched or moved; they are
only added to `skills.disabled` so they leave the index. Reversible with --revert. Re-runnable (idempotent).

  python build_superskills.py --home <profile HERMES_HOME>            # dry run: prints the plan
  python build_superskills.py --home <profile HERMES_HOME> --apply    # writes suites + updates config.yaml
  python build_superskills.py --home <profile HERMES_HOME> --revert   # removes suites, re-enables the members
"""
import argparse, datetime, json, pathlib, re, shutil, sys

EXCLUDED = {'.git', '.github', '.hub', '.archive', '.curator_backups', '.locks', '.venv', 'venv', 'node_modules',
            'site-packages', '__pycache__', '.tox', '.nox', '.pytest_cache', '.mypy_cache', '.ruff_cache'}
SUPPORT = {'references', 'templates', 'assets', 'scripts'}
SUITES = 'suites'
GEN_MARK = 'build_superskills.py'
PROMPT_DESC_LIMIT = 60          # Hermes truncates every index description to this (57 chars + "...")

# Short scope phrases for the index line (first ~57 chars are all the model sees there) and the shared header.
PURPOSE = {
    'autonomous-ai-agents': 'Coding agents: Claude Code, Codex, OpenCode, Hermes',
    'blockchain': 'Web3: Alchemy API, Solidity/Foundry, agent gateway',
    'creative': 'Design/art: p5js, manim, infographics, diagrams, web',
    'devops': 'Deploy: Vercel for GitHub, git deploys',
    'email': 'Email: inbox triage, himalaya CLI',
    'finance': 'Finance: investor materials and outreach',
    'media': 'Files/media: uploaded files, PDF read, YouTube, GIF',
    'operations': 'Ops: Hermes orchestration, local desktop control',
    'productivity': 'Office/SaaS: pdf, docx, xlsx, pptx, Notion, Google, Box',
    'research': 'Research: arXiv, deep research, citations, market intel',
    'security': 'Security: code/system audit and review',
    'software-development': 'Coding: debug, TDD, review, API/MCP, GitHub, frontend',
    'video-production': 'Video/motion/3D/voice/AI media: HeyGen, Remotion, GSAP',
    'note-taking': 'Notes: Obsidian vaults',
    'social-media': 'Social media posting and research',
    'web': 'Web: blocked-page recovery',
}


# ---------------------------------------------------------------- tiny YAML-frontmatter reader (name/description/platforms)
def _unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        return re.sub(r'\\(["\\/]|n|t)', lambda m: {'n': ' ', 't': ' '}.get(m.group(1), m.group(1)), v[1:-1])
    if len(v) >= 2 and v[0] == "'" and v[-1] == "'":
        return v[1:-1].replace("''", "'")
    return v


def read_frontmatter(path: pathlib.Path) -> dict:
    text = path.read_text(encoding='utf-8-sig', errors='replace')
    lines = text.splitlines()
    if not lines or lines[0].strip() != '---':
        return {}
    fm_lines = []
    for ln in lines[1:]:
        if ln.strip() == '---':
            break
        fm_lines.append(ln)
    out, i = {}, 0
    while i < len(fm_lines):
        m = re.match(r'^([A-Za-z_][\w-]*):\s*(.*)$', fm_lines[i])
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).rstrip()
        i += 1
        if val[:1] in ('|', '>'):
            buf = []
            while i < len(fm_lines) and (fm_lines[i].startswith((' ', '\t')) or not fm_lines[i].strip()):
                buf.append(fm_lines[i].strip())
                i += 1
            out[key] = (' ' if val[0] == '>' else ' ').join(b for b in buf if b)
        elif val == '':
            nested = []
            while i < len(fm_lines) and (fm_lines[i].startswith((' ', '\t', '-')) or not fm_lines[i].strip()):
                nested.append(fm_lines[i])
                i += 1
            if key == 'platforms':
                out[key] = [re.sub(r'^\s*-\s*', '', n).strip() for n in nested if n.strip().startswith('-')]
            else:
                out[key] = ' '.join(n.strip() for n in nested if n.strip() and not n.strip().startswith('-'))
        elif val.startswith('"') and not re.search(r'(?<!\\)"\s*$', val[1:] if len(val) > 1 else ''):
            buf = [val]
            while i < len(fm_lines):
                buf.append(fm_lines[i].strip())
                done = re.search(r'(?<!\\)"\s*$', fm_lines[i])
                i += 1
                if done:
                    break
            out[key] = _unquote(' '.join(buf))
        elif val.startswith('[') and val.endswith(']'):
            out[key] = [_unquote(x) for x in val[1:-1].split(',') if x.strip()]
        else:
            out[key] = _unquote(val)
    return out


def norm_desc(d) -> str:
    s = re.sub(r'\s+', ' ', str(d or '')).strip().strip('\'"')
    return re.sub(r'^[>|]-?\s+', '', s)          # ported skills carry a stray YAML "> " marker


def first_sentence(d: str, limit: int = 120) -> str:
    d = norm_desc(d)
    first = re.split(r'(?<=[.!?])\s', d, maxsplit=1)[0]
    first = first if first else d
    return (first[:limit - 1].rstrip() + '…') if len(first) > limit else first


def platform_ok(fm: dict, plat: str) -> bool:
    p = fm.get('platforms')
    if not p:
        return True
    if isinstance(p, str):
        p = [p]
    p = [str(x).lower() for x in p]
    return any(x in p for x in (plat, 'win32' if plat == 'windows' else plat, 'all', 'any'))


# ---------------------------------------------------------------- config.yaml skills.disabled editing (text level, keeps comments)
def read_cfg(path: pathlib.Path):
    raw = path.read_bytes().decode('utf-8-sig')
    nl = '\r\n' if '\r\n' in raw else '\n'
    return raw.split(nl), nl


def get_disabled(lines):
    s = next((i for i, l in enumerate(lines) if re.match(r'^skills:\s*(#.*)?$', l)), -1)
    if s < 0:
        return set(), (-1, -1, -1)
    e = next((i for i in range(s + 1, len(lines)) if re.match(r'^[A-Za-z_]', lines[i])), len(lines))
    d = next((i for i in range(s + 1, e) if re.match(r'^\s{2}disabled:', lines[i])), -1)
    if d < 0:
        return set(), (s, e, -1)
    names, j = set(), d + 1
    rest = lines[d].split(':', 1)[1].strip()
    if rest.startswith('['):
        names = {_unquote(x) for x in rest.strip('[]').split(',') if x.strip()}
        return names, (s, e, d, d + 1)
    while j < e and re.match(r'^\s*-\s+\S', lines[j]):
        names.add(_unquote(re.sub(r'\s+#.*$', '', re.sub(r'^\s*-\s+', '', lines[j]))))
        j += 1
    return names, (s, e, d, j)


def set_disabled(lines, names):
    cur, loc = get_disabled(lines)
    block = ['  disabled:'] + [f'    - {n}' for n in sorted(names)] if names else ['  disabled: []']
    if loc[0] < 0:
        return lines + ['skills:'] + block
    if len(loc) == 3 or loc[2] < 0:
        return lines[:loc[0] + 1] + block + lines[loc[0] + 1:]
    return lines[:loc[2]] + block + lines[loc[3]:]


# ---------------------------------------------------------------- discovery
def discover(skills_dir: pathlib.Path, plat: str):
    cats = {}
    for cat_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir() and p.name not in EXCLUDED and p.name != SUITES):
        members = []
        for root, dirs, files in __import__('os').walk(cat_dir):
            has = 'SKILL.md' in files
            dirs[:] = sorted(d for d in dirs if d not in EXCLUDED and not (has and d in SUPPORT))
            if 'SKILL.md' in files and pathlib.Path(root) != cat_dir:
                sp = pathlib.Path(root) / 'SKILL.md'
                fm = read_frontmatter(sp)
                name = fm.get('name') or pathlib.Path(root).name
                raw = sp.read_text(encoding='utf-8-sig', errors='replace')[:6000]
                tm = re.search(r'^\s+tags:\s*\[(.*?)\]', raw, re.M)
                tags = [x.strip().strip('"\'') for x in tm.group(1).split(',') if x.strip()][:4] if tm else []
                members.append({'name': str(name), 'tags': tags, 'desc': norm_desc(fm.get('description')), 'path': sp,
                                'rel': sp.relative_to(cat_dir).as_posix(), 'ok': platform_ok(fm, plat)})
        if members:
            cats[cat_dir.name] = members
    return cats


def index_cost(m) -> int:
    d = m['desc']
    d = d[:PROMPT_DESC_LIMIT - 3] + '...' if len(d) > PROMPT_DESC_LIMIT else d
    return len(f'    - {m["name"]}: {d}') + 1


def families(members):
    from collections import Counter
    c = Counter(m['name'].split('-')[0] for m in members)
    return {k for k, v in c.items() if v >= 3}


def lead_text(cat, members) -> str:
    base = PURPOSE.get(cat) or (cat.replace('-', ' ').capitalize() + ' guides')
    return base


def row(m, big_family: bool) -> str:
    scope = first_sentence(m['desc'], 70 if big_family else 100)
    tags = '' if big_family or not m.get('tags') else ' (' + ', '.join(t.lower() for t in m['tags'][:4]) + ')'
    odd = '' if m['rel'] == f'{m["name"]}/SKILL.md' else f' -> {m["rel"]}'     # only when the folder differs from the name
    return f'- {m["name"]} | {scope}{tags}{odd}'


def build_suite_md(cat, members, guides_root: str, prof_label: str) -> str:
    n = len(members)
    lead = lead_text(cat, members)
    desc = f'{lead} ({n} guides) - router, open the matching guide'
    fam = families(members)
    all_tags = []
    for m in members:
        for t in m.get('tags', []):
            if t.lower() not in all_tags and len(all_tags) < 14:
                all_tags.append(t.lower())
    # Layout follows the open Agent Skills pattern "domain-specific organization": SKILL.md = overview + navigation,
    # detail stays one level down in the guides. Section order follows the Hermes body convention.
    lines = ['---', f'name: {cat}-suite', f'description: "{desc.replace(chr(34), chr(39))}"', 'version: 1.1.0',
             'platforms: [windows, macos, linux]',
             'metadata:', '  hermes:', f'    tags: [suite, {cat}]', f'    generated_by: {GEN_MARK}',
             f'    members: {n}', '---', '',
             f'# {cat}-suite ({n} guides)', '',
             f'Router for the whole `{cat}` skill area. The {n} individual skills were folded into this one entry so they stop costing prompt tokens on every request; '
             'each guide is the original SKILL.md, unchanged and still on disk.', '',
             '## When to Use', '',
             f'- Any task in this area: {lead.split(":", 1)[1].strip() if ":" in lead else lead}.',
             '- Not for tasks outside this area - do not open a guide just because it is nearby.', '',
             '## Procedure', '',
             '1. Scan the table below and pick the 1-3 guides whose scope matches the task (rows: `name | scope (tags)`).',
             f'2. Open each with `read_file` on the ABSOLUTE path `{guides_root}/<name>/SKILL.md` - replace `<name>` with the guide name. '
             f'If a row ends with `-> other/path/SKILL.md`, use `{guides_root}/other/path/SKILL.md` instead. The guides are NOT inside this suite\'s own folder.',
             '3. Read a guide\'s `references/`, `templates/`, `scripts/` (same folder as its SKILL.md) only when the guide points to them.',
             '4. Follow the guide exactly like a normal skill. In a guide, `${HERMES_SKILL_DIR}` means that guide\'s own folder. Install any dependency it names.',
             '5. Done when you can name the guide(s) you followed and each step finished or was reported as blocked.', '',
             '## Pitfalls', '',
             '- Guide names are not skills: `skill_view("<guide>")` fails. Open guides with `read_file` on the absolute path above.',
             '- If no guide fits, say so; do not improvise from the names alone.',
             '- A `[DEPRECATED]` scope points to its replacement - open the replacement instead.',
             '- Do not edit a guide here; patch the original with `skill_manage` or `patch` on its path.', '',
             '## Guides', '']
    done = set()
    for f in sorted(fam):
        grp = [m for m in members if m['name'].split('-')[0] == f]
        big = len(grp) >= 6
        lines.append(f'### {f}-* ({len(grp)})')
        for m in grp:
            lines.append(row(m, big))
            done.add(m['name'])
        lines.append('')
    rest = [m for m in members if m['name'] not in done]
    if rest:
        lines.append('### ' + ('Other' if fam else 'All') + f' ({len(rest)})')
        for m in rest:
            lines.append(row(m, False))
        lines.append('')
    return '\n'.join(lines)


def suite_line_cost(cat, members) -> int:
    n = len(members)
    d = f'{lead_text(cat, members)} ({n} guides) - router, open the matching guide'
    d = d[:PROMPT_DESC_LIMIT - 3] + '...' if len(d) > PROMPT_DESC_LIMIT else d
    return len(f'    - {cat}-suite: {d}') + 1


def keywords_for(members, budget: int = 105) -> str:
    """Extra routing keywords the 57-char index window cannot show: families (gsap-*) first, then the shortest member names."""
    fam = sorted(families(members))
    out = [f'{f}-*' for f in fam]
    singles = sorted((m['name'] for m in members if m['name'].split('-')[0] not in fam), key=lambda s: (len(s), s))
    text = ', '.join(out)
    for s in singles:
        nxt = (text + ', ' + s) if text else s
        if len(nxt) > budget:
            break
        text = nxt
    return text


def header_text(plan) -> str:
    parts = [f'{cat}: {keywords_for(mem)}' for cat, mem in plan]
    return ('Each suite = one skill area folded into a single entry (nothing deleted). Load the suite itself with skill_view(<area>-suite); '
            'the guide names below are NOT skills (skill_view on them fails) - open a guide with read_file at the path given in its suite. '
            'Contents - ' + '; '.join(parts) + '.')


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--home', required=True, help='profile HERMES_HOME (contains config.yaml and skills/)')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--revert', action='store_true')
    ap.add_argument('--min-members', type=int, default=2)
    ap.add_argument('--exclude', default='', help='comma-separated categories to leave alone')
    ap.add_argument('--keep', default='', help='comma-separated skill names to keep individually indexed (never folded)')
    ap.add_argument('--keep-used', type=int, default=12, help='also keep the N most-used skills per skills/.usage.json (0 = off)')
    ap.add_argument('--platform', default='windows')
    a = ap.parse_args()

    home = pathlib.Path(a.home)
    skills_dir, cfg_path = home / 'skills', home / 'config.yaml'
    suites_dir = skills_dir / SUITES
    manifest_path = suites_dir / '.manifest.json'
    if not skills_dir.is_dir() or not cfg_path.is_file():
        sys.exit(f'not a Hermes home: {home}')
    prev = json.loads(manifest_path.read_text('utf-8')) if manifest_path.is_file() else {'disabled': []}
    prev_dis = set(prev.get('disabled', []))
    lines, nl = read_cfg(cfg_path)
    cur_dis, _ = get_disabled(lines)
    user_dis = cur_dis - prev_dis                      # disabled by someone else: leave exactly as is
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')

    if a.revert:
        if not manifest_path.is_file():
            sys.exit('nothing to revert (no manifest)')
        new_lines = set_disabled(lines, user_dis)
        shutil.copy2(cfg_path, f'{cfg_path}.bak-superskills-{stamp}')
        cfg_path.write_bytes(nl.join(new_lines).encode('utf-8'))
        shutil.rmtree(suites_dir)
        print(f'reverted: removed {suites_dir}, re-enabled {len(prev_dis)} skills')
        return

    excl = {x.strip() for x in a.exclude.split(',') if x.strip()}
    keep = {x.strip() for x in a.keep.split(',') if x.strip()}
    usage_path = skills_dir / '.usage.json'
    if a.keep_used and usage_path.is_file():
        try:
            usage = json.loads(usage_path.read_text('utf-8'))
            used = sorted(((v.get('use_count', 0) + v.get('view_count', 0), k) for k, v in usage.items()
                           if isinstance(v, dict) and not k.endswith('-suite') and (v.get('use_count', 0) or v.get('view_count', 0))), reverse=True)
            keep |= {k for _, k in used[:a.keep_used]}
        except Exception as e:
            print('note: could not read .usage.json:', e)
    cats = discover(skills_dir, a.platform)
    plan, standalone = [], []
    print('kept individually (explicit or most-used):', ', '.join(sorted(keep)) or '(none)')
    for cat, mem in cats.items():
        elig = [m for m in mem if m['ok'] and (m['name'] not in user_dis) and m['name'] not in keep]
        if cat in excl or len(elig) < a.min_members:
            standalone += [m for m in elig]
            continue
        plan.append((cat, sorted(elig, key=lambda m: m['name'])))
    old_total = sum(index_cost(m) for _, mem in plan for m in mem)
    new_total = sum(suite_line_cost(c, mem) for c, mem in plan)
    hdr = header_text(plan)
    new_total += len(f'  {SUITES}: {hdr}') + 1
    print(f'home: {home}')
    print(f'{"category":<24}{"guides":>7}{"old idx chars":>15}{"suite line":>12}')
    for cat, mem in plan:
        print(f'{cat:<24}{len(mem):>7}{sum(index_cost(m) for m in mem):>15}{suite_line_cost(cat, mem):>12}')
    print(f'{"TOTAL (+header)":<24}{sum(len(m) for _, m in plan):>7}{old_total:>15}{new_total:>12}   ->  saves ~{old_total - new_total} chars ({(old_total - new_total) * 100 // max(old_total, 1)}%)')
    print(f'left as individual skills: {len(standalone)}  |  disabled by someone else (kept): {len(user_dis)}')
    if not a.apply:
        print('dry run - nothing written (use --apply)')
        return

    # write suites
    suites_dir.mkdir(exist_ok=True)
    for old in suites_dir.iterdir():
        if old.is_dir():
            shutil.rmtree(old)
    for cat, mem in plan:
        d = suites_dir / f'{cat}-suite'
        d.mkdir(exist_ok=True)
        root = (skills_dir / cat).as_posix()
        (d / 'SKILL.md').write_text(build_suite_md(cat, mem, root, home.name), encoding='utf-8', newline='\n')
    (suites_dir / 'DESCRIPTION.md').write_text('---\ndescription: ' + json.dumps(hdr, ensure_ascii=False) + '\n---\n', encoding='utf-8', newline='\n')
    member_names = sorted({m['name'] for _, mem in plan for m in mem})
    manifest_path.write_text(json.dumps({'generated': stamp, 'tool': GEN_MARK, 'disabled': member_names,
                                         'suites': {c: [m['name'] for m in mem] for c, mem in plan}}, indent=1), encoding='utf-8')
    new_lines = set_disabled(lines, user_dis | set(member_names))
    shutil.copy2(cfg_path, f'{cfg_path}.bak-superskills-{stamp}')
    cfg_path.write_bytes(nl.join(new_lines).encode('utf-8'))
    print(f'applied: {len(plan)} suites in {suites_dir}; skills.disabled now {len(user_dis | set(member_names))} names; backup config.yaml.bak-superskills-{stamp}')


if __name__ == '__main__':
    main()
