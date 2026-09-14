"""Minimal, stdlib-only loader for the YAML subset this repo's own config
files (plan-rules.yaml, datasources.yaml) use: block mappings and
sequences (2-space indent), flow-style `[a, b]` lists, single/double
quoted scalars (with `\\"`/`\\\\` escaping), plain scalars, booleans, and
`#` comments. Not a general YAML parser -- same spirit as hoist.awk and
validate_plan.py's own line/indentation-driven plan parser. Only meant to
load config this repo authors itself; don't feed it arbitrary YAML.
"""
import re


def _strip_comment(line):
    out = []
    in_s = in_d = False
    for c in line:
        if c == "'" and not in_d:
            in_s = not in_s
        elif c == '"' and not in_s:
            in_d = not in_d
        elif c == "#" and not in_s and not in_d:
            break
        out.append(c)
    return "".join(out).rstrip()


def _tokenize(text):
    lines = []
    for raw in text.splitlines():
        stripped = _strip_comment(raw.replace("\t", "    "))
        if stripped.strip() == "":
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        lines.append((indent, stripped.strip()))
    return lines


def _unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _parse_flow_list(s):
    inner = s[1:-1].strip()
    if inner == "":
        return []
    items, cur, in_s, in_d = [], "", False, False
    for c in inner:
        if c == "'" and not in_d:
            in_s = not in_s
        elif c == '"' and not in_s:
            in_d = not in_d
        if c == "," and not in_s and not in_d:
            items.append(_parse_scalar(cur))
            cur = ""
            continue
        cur += c
    if cur.strip() != "":
        items.append(_parse_scalar(cur))
    return items


def _parse_scalar(s):
    s = s.strip()
    if s == "":
        return None
    if len(s) >= 2 and s.startswith('"') and s.endswith('"'):
        return _unescape(s[1:-1])
    if len(s) >= 2 and s.startswith("'") and s.endswith("'"):
        return s[1:-1].replace("''", "'")
    if s.startswith("[") and s.endswith("]"):
        return _parse_flow_list(s)
    if s in ("true", "True"):
        return True
    if s in ("false", "False"):
        return False
    if s in ("null", "~", "None"):
        return None
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d+\.\d+", s):
        return float(s)
    return s


def _split_key_value(content):
    in_s = in_d = False
    for i, c in enumerate(content):
        if c == "'" and not in_d:
            in_s = not in_s
        elif c == '"' and not in_s:
            in_d = not in_d
        elif c == ":" and not in_s and not in_d:
            if i + 1 == len(content) or content[i + 1] == " ":
                return content[:i].strip(), content[i + 1:].strip()
    return None, None


class _Cursor:
    def __init__(self, lines):
        self.lines = lines
        self.i = 0

    def peek(self):
        return self.lines[self.i] if self.i < len(self.lines) else None

    def advance(self):
        self.i += 1


def _parse_block(cur, indent):
    tok = cur.peek()
    if tok is None or tok[0] != indent:
        return None
    if tok[1].startswith("- "):
        return _parse_sequence(cur, indent)
    return _parse_mapping(cur, indent)


def _parse_value_or_nested(cur, key, value, parent_indent, mapping):
    if value != "":
        mapping[key] = _parse_scalar(value)
        return
    nxt = cur.peek()
    if nxt and nxt[0] > parent_indent:
        mapping[key] = _parse_block(cur, nxt[0])
    else:
        mapping[key] = None


def _parse_sequence(cur, indent):
    items = []
    while True:
        tok = cur.peek()
        if tok is None or tok[0] != indent or not tok[1].startswith("- "):
            break
        _, content = tok
        rest = content[2:]
        cur.advance()

        if rest == "":
            nxt = cur.peek()
            items.append(_parse_block(cur, nxt[0]) if nxt and nxt[0] > indent else None)
            continue

        key, value = _split_key_value(rest)
        if key is None:
            items.append(_parse_scalar(rest))
            continue

        # A sequence item that's a mapping: its first key:value is inline
        # after "- "; further keys of the SAME item follow at indent+2.
        item_indent = indent + 2
        mapping = {}
        _parse_value_or_nested(cur, key, value, indent + 1, mapping)
        while True:
            nxt = cur.peek()
            if nxt is None or nxt[0] != item_indent or nxt[1].startswith("- "):
                break
            _, kv = nxt
            k, v = _split_key_value(kv)
            cur.advance()
            if k is None:
                continue
            _parse_value_or_nested(cur, k, v, item_indent, mapping)
        items.append(mapping)
    return items


def _parse_mapping(cur, indent):
    result = {}
    while True:
        tok = cur.peek()
        if tok is None or tok[0] != indent or tok[1].startswith("- "):
            break
        _, content = tok
        key, value = _split_key_value(content)
        cur.advance()
        if key is None:
            continue
        _parse_value_or_nested(cur, key, value, indent, result)
    return result


def load(text):
    lines = _tokenize(text)
    if not lines:
        return {}
    cur = _Cursor(lines)
    return _parse_block(cur, lines[0][0]) or {}


def load_file(path):
    with open(path) as f:
        return load(f.read())
