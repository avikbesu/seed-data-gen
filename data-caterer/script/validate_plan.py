#!/usr/bin/env python3
"""Rule-based validator for data-caterer plan YAML files.

Not a general YAML parser -- these are line/indentation-driven checks
tailored to the plan shape this repo's plans use (2-space indent,
`dataSources: -> steps: -> fields:` all as `- name: "..."` lists -- see
config/generator/plan/banking.yaml / retail.yaml). Rules live in
plan-rules.yaml (next to this file, loaded via plan_yaml.py); see that
file's header comment and CONTRIBUTING.md's "Writing a plan file" section
for what each rule encodes and why.

Usage: validate_plan.py --rules plan-rules.yaml [--file PATH[:LABEL]]...
`--file` may be given more than once; PATH is what's read from disk,
LABEL (defaults to PATH) is what's shown in messages -- used so a
pre-commit hook can validate a staged blob written to a temp path while
still reporting the real repo-relative path.
"""
import argparse
import re
import sys

import plan_yaml


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def trimmed(line):
    return line.lstrip(" ")


class Field:
    def __init__(self, name, start, end, lines):
        self.name = name
        self.start = start  # 1-indexed line number
        self.end = end
        self.block = "\n".join(lines[start - 1:end])
        m = re.search(r'type: *"([a-zA-Z]+)"', self.block)
        self.type = m.group(1) if m else None


class Step:
    def __init__(self, name, start, end):
        self.name = name
        self.start = start
        self.end = end
        self.has_count = False
        self.has_fields = False
        self.fields = []  # list[Field]


class DataSource:
    def __init__(self, name, start, end):
        self.name = name
        self.start = start
        self.end = end
        self.steps = []  # list[Step]


class Plan:
    """Parses a plan file's text into the structure the rules need."""

    def __init__(self, label, lines):
        self.label = label
        self.lines = lines  # 0-indexed list of raw lines (no line numbers)
        self.sys = re.sub(r"\.yaml$", "", label.rsplit("/", 1)[-1])
        self.datasources = self._parse_datasources()
        self.fk_entries = self._parse_foreign_keys()

    @property
    def steps(self):
        return [s for ds in self.datasources for s in ds.steps]

    def _parse_datasources(self):
        lines = self.lines
        n = len(lines)
        ds_line = None
        for i, l in enumerate(lines):
            if l.startswith("dataSources:"):
                ds_line = i
                break
        if ds_line is None:
            return []

        item_ind = None
        i = ds_line + 1
        while i < n:
            l = lines[i]
            if indent_of(l) == 0 and trimmed(l).strip() != "":
                break
            t = trimmed(l).strip()
            if t.startswith('- name: "'):
                item_ind = indent_of(l)
                break
            i += 1
        if item_ind is None:
            return []

        datasources = []
        cur_start = None
        cur_name = None
        i = ds_line + 1
        while i < n:
            l = lines[i]
            t = trimmed(l).rstrip("\n")
            if t.strip() == "":
                i += 1
                continue
            ind = indent_of(l)
            if ind < item_ind:
                break
            if ind == item_ind and t.strip().startswith('- name: "'):
                if cur_start is not None:
                    datasources.append(self._build_datasource(cur_name, cur_start, i))
                cur_name = re.sub(r'^- name: "', "", t.strip())
                cur_name = re.sub(r'".*$', "", cur_name)
                cur_start = i + 1  # 1-indexed
            i += 1
        if cur_start is not None:
            datasources.append(self._build_datasource(cur_name, cur_start, i))
        return datasources

    def _build_datasource(self, name, start_1idx, end_1idx):
        ds = DataSource(name, start_1idx, end_1idx)
        ds.steps = self._parse_steps(start_1idx, end_1idx)
        return ds

    def _parse_steps(self, ds_start_1idx, ds_end_1idx):
        lines = self.lines
        steps_line = None
        step_ind = None
        i = ds_start_1idx - 1
        while i < ds_end_1idx:
            t = trimmed(lines[i]).strip()
            if t == "steps:":
                steps_line = i
                i += 1
                continue
            if steps_line is not None and t.startswith('- name: "'):
                step_ind = indent_of(lines[i])
                break
            i += 1
        if steps_line is None or step_ind is None:
            return []

        steps = []
        cur_start = None
        cur_name = None
        i = steps_line + 1
        while i < ds_end_1idx:
            l = lines[i]
            t = trimmed(l).rstrip("\n")
            if t.strip() == "":
                i += 1
                continue
            ind = indent_of(l)
            if ind < step_ind:
                break
            if ind == step_ind and t.strip().startswith('- name: "'):
                if cur_start is not None:
                    steps.append(self._build_step(cur_name, cur_start, i))
                cur_name = re.sub(r'^- name: "', "", t.strip())
                cur_name = re.sub(r'".*$', "", cur_name)
                cur_start = i + 1  # 1-indexed
            i += 1
        if cur_start is not None:
            steps.append(self._build_step(cur_name, cur_start, i))
        return steps

    def _build_step(self, name, start_1idx, end_1idx):
        step = Step(name, start_1idx, end_1idx)
        fields_line_0idx = None
        for i in range(start_1idx - 1, end_1idx):
            t = trimmed(self.lines[i]).strip()
            if t == "count:":
                step.has_count = True
            if t == "fields:":
                step.has_fields = True
                fields_line_0idx = i
        if fields_line_0idx is not None:
            step.fields = self._parse_fields(fields_line_0idx, end_1idx)
        return step

    def _parse_fields(self, fields_line_0idx, step_end_1idx):
        lines = self.lines
        field_ind = None
        fields = []
        cur_start = None
        cur_name = None
        i = fields_line_0idx + 1
        while i < step_end_1idx:
            l = lines[i]
            t = trimmed(l).rstrip("\n")
            if t.strip() == "":
                i += 1
                continue
            ind = indent_of(l)
            if field_ind is None:
                if t.startswith('- name: "'):
                    field_ind = ind
                else:
                    i += 1
                    continue
            if ind < field_ind:
                break
            if ind == field_ind and t.startswith('- name: "'):
                if cur_start is not None:
                    fields.append(Field(cur_name, cur_start, i, lines))
                cur_name = re.sub(r'^- name: "', "", t)
                cur_name = re.sub(r'".*$', "", cur_name)
                cur_start = i + 1  # 1-indexed
            i += 1
        if cur_start is not None:
            fields.append(Field(cur_name, cur_start, step_end_1idx, lines))
        return fields

    def options_subblock(self, step, fmt):
        """Text of a step's options.<fmt> sub-block, or None if absent."""
        lines = self.lines
        options_line = None
        options_ind = None
        for i in range(step.start - 1, step.end):
            t = trimmed(lines[i]).strip()
            if t == "options:":
                options_line = i
                options_ind = indent_of(lines[i])
                break
        if options_line is None:
            return None

        child_ind = None
        fmt_start = None
        i = options_line + 1
        while i < step.end:
            l = lines[i]
            t = trimmed(l).strip()
            if t == "":
                i += 1
                continue
            ind = indent_of(l)
            if ind <= options_ind:
                break
            if child_ind is None:
                child_ind = ind
            if ind == child_ind and t == f"{fmt}:":
                fmt_start = i
                i += 1
                break
            i += 1
        if fmt_start is None:
            return None

        block_lines = []
        i = fmt_start + 1
        while i < step.end:
            l = lines[i]
            t = trimmed(l).strip()
            if t != "":
                ind = indent_of(l)
                if ind <= child_ind:
                    break
                block_lines.append(l)
            i += 1
        return "\n".join(block_lines)

    def _parse_foreign_keys(self):
        lines = self.lines
        n = len(lines)
        fk_line = None
        for i, l in enumerate(lines):
            if l.startswith("foreignKeys:"):
                fk_line = i
                break
        if fk_line is None:
            return []

        item_ind = None
        for i in range(fk_line + 1, n):
            ind = indent_of(lines[i])
            t = trimmed(lines[i]).strip()
            if ind == 0 and t != "":
                break
            if t == "- source:":
                item_ind = ind
                break
        if item_ind is None:
            return []

        entries = []
        cur_entry = None
        section = None
        cur_gen = None
        i = fk_line + 1
        while i < n:
            raw = lines[i]
            ind = indent_of(raw)
            t = trimmed(raw).strip()
            if ind == 0 and t != "":
                break
            if t == "":
                i += 1
                continue
            if ind == item_ind and t == "- source:":
                if cur_entry is not None:
                    entries.append(cur_entry)
                cur_entry = {"source": {"line": i + 1}, "generate": []}
                section = "source"
                cur_gen = None
                i += 1
                continue
            if cur_entry is None:
                i += 1
                continue
            if section == "source":
                if t == "generate:":
                    section = "generate"
                    i += 1
                    continue
                m = re.match(r'^dataSource: *"([^"]*)"', t)
                if m:
                    cur_entry["source"]["dataSource"] = m.group(1)
                m = re.match(r'^step: *"([^"]*)"', t)
                if m:
                    cur_entry["source"]["step"] = m.group(1)
                m = re.match(r"^fields: *(\[.*\])", t)
                if m:
                    cur_entry["source"]["fields"] = re.findall(r'"([^"]*)"', m.group(1))
            elif section == "generate":
                if t.startswith("- dataSource:"):
                    cur_gen = {"line": i + 1}
                    cur_entry["generate"].append(cur_gen)
                    m = re.match(r'^- dataSource: *"([^"]*)"', t)
                    if m:
                        cur_gen["dataSource"] = m.group(1)
                elif cur_gen is not None:
                    m = re.match(r'^step: *"([^"]*)"', t)
                    if m:
                        cur_gen["step"] = m.group(1)
                    m = re.match(r"^fields: *(\[.*\])", t)
                    if m:
                        cur_gen["fields"] = re.findall(r'"([^"]*)"', m.group(1))
            i += 1
        if cur_entry is not None:
            entries.append(cur_entry)
        return entries


class Validator:
    def __init__(self, rules):
        self.rules = rules
        self.errors = []

    def fail(self, plan, line_no, message):
        self.errors.append(f"{plan.label}:{line_no}: {message}")

    def err(self, plan, message):
        self.errors.append(f"{plan.label}: {message}")

    def run(self, plan):
        self._check_line_bans(plan)
        self._check_required_top_level_keys(plan)
        self._check_dataSources_present(plan)
        self._check_datasources(plan)
        self._check_duplicate_fk_targets(plan)
        self._check_foreign_key_field_references(plan)
        self._check_dual_format_options(plan)

    def _check_line_bans(self, plan):
        for i, raw in enumerate(plan.lines):
            line_no = i + 1
            t = trimmed(raw).rstrip("\n")
            if t.lstrip().startswith("#"):
                continue
            for rule in self.rules.get("line_bans", []):
                subject = raw if rule["on"] == "raw" else t
                if not re.search(rule["pattern"], subject):
                    continue
                excl = rule.get("exclude_pattern")
                if excl and re.search(excl, raw):
                    continue
                self.fail(plan, line_no, rule["message"])
            self._check_path_prefix(plan, line_no, raw)

    def _check_path_prefix(self, plan, line_no, raw):
        rule = self.rules.get("path_prefix")
        if not rule:
            return
        m = re.search(rule["key"] + r': *"([^"]*)"', trimmed(raw))
        if not m:
            return
        value = m.group(1)
        expected = rule["template"].format(sys=plan.sys)
        if not value.startswith(expected):
            self.fail(plan, line_no, rule["message"].format(value=value, expected=expected))

    def _check_required_top_level_keys(self, plan):
        for key in self.rules.get("required_top_level_keys", []):
            if not any(l.startswith(key + ":") for l in plan.lines):
                self.err(plan, f"missing required top-level key '{key}:'")

    def _check_dataSources_present(self, plan):
        if not any(l.startswith("dataSources:") for l in plan.lines):
            self.err(plan, "no top-level 'dataSources:' key found")
        elif not plan.datasources:
            self.err(plan, "no dataSources[] entries (or no steps under them) found")

    def _check_datasources(self, plan):
        required = self.rules.get("required_datasource_keys", [])
        for ds in plan.datasources:
            if "steps" in required and not ds.steps:
                self.fail(plan, ds.start, f"dataSources entry '{ds.name}' has no 'steps:' key (or no steps)")
            for step in ds.steps:
                self._check_step(plan, step)

    def _check_step(self, plan, step):
        required = self.rules.get("required_step_keys", [])
        if "count" in required and not step.has_count:
            self.fail(plan, step.start, f"step '{step.name}' has no 'count:' key")
        if "fields" in required and not step.has_fields:
            self.fail(plan, step.start, f"step '{step.name}' has no 'fields:' key")
        self._check_fields(plan, step)

    def _check_fields(self, plan, step):
        names = {f.name for f in step.fields}
        for field in step.fields:
            self._check_bucket_conventions(plan, field)
            self._check_type_construct_conflicts(plan, field)
            self._check_literal_collision(plan, field, names)

    def _check_bucket_conventions(self, plan, field):
        for rule in self.rules.get("field_suffix_conventions", []):
            if not field.name.endswith(rule["suffix"]):
                continue
            ok = field.type == rule["require_type"]
            for key, value in rule.get("require_options", {}).items():
                if not re.search(rf"{key}: *{re.escape(value)}\b", field.block):
                    ok = False
            if not ok:
                self.fail(plan, field.start, rule["message"].format(
                    field=field.name, suffix=rule["suffix"], require_type=rule["require_type"]))

    def _check_type_construct_conflicts(self, plan, field):
        for rule in self.rules.get("type_construct_conflicts", []):
            if field.type != rule["type"]:
                continue
            if re.search(re.escape(rule["forbidden_construct"]) + r":", field.block):
                self.fail(plan, field.start, rule["message"].format(field=field.name))

    def _check_literal_collision(self, plan, field, sibling_names):
        rule = self.rules.get("literal_field_name_collision", {})
        if not rule.get("enabled"):
            return
        for lit in re.findall(r"'([A-Za-z_][A-Za-z0-9_]*)'", field.block):
            if lit in sibling_names:
                self.fail(plan, field.start, rule["message"].format(field=field.name, literal=lit))

    def _check_duplicate_fk_targets(self, plan):
        rule = self.rules.get("duplicate_foreign_key_targets", {})
        if not rule.get("enabled"):
            return
        seen = {}
        for entry in plan.fk_entries:
            for gen in entry["generate"]:
                step = gen.get("step")
                line = gen.get("line")
                if step is None:
                    continue
                if step in seen:
                    self.fail(plan, line, rule["message"].format(step=step, first_line=seen[step]))
                else:
                    seen[step] = line

    def _check_foreign_key_field_references(self, plan):
        rule = self.rules.get("foreign_key_field_references", {})
        if not rule.get("enabled"):
            return
        ds_by_name = {ds.name: ds for ds in plan.datasources}
        for entry in plan.fk_entries:
            self._check_fk_ref(plan, rule, "source", entry["source"], ds_by_name)
            for gen in entry["generate"]:
                self._check_fk_ref(plan, rule, "generate", gen, ds_by_name)

    def _check_fk_ref(self, plan, rule, kind, ref, ds_by_name):
        line = ref.get("line", 0)
        dsname = ref.get("dataSource")
        stepname = ref.get("step")
        fields = ref.get("fields", [])

        if dsname not in ds_by_name:
            self.fail(plan, line, rule["bad_datasource_message"].format(kind=kind, value=dsname))
            return
        ds = ds_by_name[dsname]

        step_by_name = {s.name: s for s in ds.steps}
        if stepname not in step_by_name:
            self.fail(plan, line, rule["bad_step_message"].format(kind=kind, value=stepname, datasource=dsname))
            return
        step = step_by_name[stepname]

        field_names = {f.name for f in step.fields}
        for fname in fields:
            if fname not in field_names:
                self.fail(plan, line, rule["bad_field_message"].format(kind=kind, value=fname, step=stepname))

    def _check_dual_format_options(self, plan):
        rule = self.rules.get("dual_format_options", {})
        if not rule.get("enabled"):
            return
        registry_path = rule["registry"]
        try:
            registry = plan_yaml.load_file(registry_path)
        except OSError as e:
            self.err(plan, f"dual_format_options: can't read registry {registry_path}: {e}")
            return

        formats = registry.get("formats", {})
        format_names = ", ".join(sorted(formats.keys()))
        for step in plan.steps:
            for fmt, spec in formats.items():
                block = plan.options_subblock(step, fmt)
                if block is None:
                    self.fail(plan, step.start, rule["missing_format_message"].format(
                        step=step.name, format=fmt, registry=registry_path, formats=format_names))
                    continue
                for key in spec.get("required_keys", []):
                    if not re.search(rf"{re.escape(key)}: ", block):
                        self.fail(plan, step.start, rule["missing_key_message"].format(
                            step=step.name, format=fmt, key=key, registry=registry_path))


def parse_files_arg(entries):
    files = []
    for entry in entries:
        if ":" in entry:
            path, label = entry.split(":", 1)
        else:
            path, label = entry, entry
        files.append((path, label))
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules", required=True, help="path to plan-rules.yaml")
    parser.add_argument("--file", dest="files", action="append", required=True,
                         help="PATH[:LABEL] of a plan file to validate; repeatable")
    args = parser.parse_args()

    rules = plan_yaml.load_file(args.rules)

    overall_ok = True
    for path, label in parse_files_arg(args.files):
        with open(path) as f:
            lines = f.read().splitlines()
        plan = Plan(label, lines)
        v = Validator(rules)
        v.run(plan)
        if v.errors:
            overall_ok = False
            for e in v.errors:
                print(e)
            print(f"{label}: {len(v.errors)} issue(s) found")
        else:
            print(f"{label}: OK")

    sys.exit(0 if overall_ok else 1)


if __name__ == "__main__":
    main()
