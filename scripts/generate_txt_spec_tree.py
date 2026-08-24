"""Module to generate a mirrored, compact plain-text Matrix Spec tree.

This script parses raw markdown files and replaces Hugo shortcodes with inline,
fully resolved schema and event definitions translated into clean TypeScript.
"""

import argparse
import json
import os
import re
from pathlib import Path

import yaml

DATA_DIR = Path("data")
DEFAULT_OUTPUT_ROOT = Path("spec")
DEFAULT_SOURCE_ROOTS = (Path("content"), Path("proposals"))


def _load_ref_file(full_path):
    """Helper to load json or yaml files."""
    with open(full_path, "r", encoding="utf-8") as f:
        if str(full_path).endswith(".json"):
            return json.load(f)
        return yaml.safe_load(f)


def resolve_refs(schema, base_dir):
    """Recursively resolves $ref keys relative to the base schema directory."""
    if isinstance(schema, list):
        return [resolve_refs(item, base_dir) for item in schema]
    if not isinstance(schema, dict):
        return schema

    if "$ref" in schema and not schema["$ref"].startswith("#"):
        ref_path = schema["$ref"]
        full_path = os.path.normpath(os.path.join(base_dir, ref_path))
        if os.path.exists(full_path):
            ref_data = _load_ref_file(full_path)
            resolved = resolve_refs(ref_data, os.path.dirname(full_path))
            merged = {**resolved} if isinstance(resolved, dict) else resolved
            if isinstance(merged, dict):
                for k, v in schema.items():
                    if k != "$ref":
                        merged[k] = resolve_refs(v, base_dir)
            return merged

    return {k: resolve_refs(v, base_dir) for k, v in schema.items()}


def resolve_all_of(schema):
    """Flattens allOf array elements into a single cohesive schema object."""
    if not isinstance(schema, dict):
        return schema
    for k, v in list(schema.items()):
        if isinstance(v, (dict, list)):
            schema[k] = resolve_all_of(v)
    if "allOf" in schema:
        all_of = schema.pop("allOf")
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        for sub in all_of:
            flat_sub = resolve_all_of(sub)
            if isinstance(flat_sub, dict):
                properties.update(flat_sub.get("properties", {}))
                for req in flat_sub.get("required", []):
                    if req not in required:
                        required.append(req)
                if "description" not in schema and "description" in flat_sub:
                    schema["description"] = flat_sub["description"]
        schema["properties"] = properties
        schema["required"] = required
    return schema


def json_schema_to_typescript(schema, depth=0):
    """Translate a resolved JSON Schema into a compact TypeScript interface."""
    if not isinstance(schema, dict):
        return "any"

    fmt = f" /* {schema['format']} */" if "format" in schema else ""

    if "enum" in schema:
        variants = [f'"{x}"' if isinstance(x, str) else str(x) for x in schema["enum"]]
        return " | ".join(variants) + fmt

    t = schema.get("type", "object")
    if t == "object":
        return _object_schema_to_ts(schema, depth) + fmt
    if t == "array":
        return _array_schema_to_ts(schema, depth) + fmt

    return _primitive_schema_to_ts(t) + fmt


def _primitive_schema_to_ts(type_str):
    """Maps primitive JSON Schema types to TS types."""
    if type_str in ("integer", "number"):
        return "number"
    if type_str == "boolean":
        return "boolean"
    if type_str == "string":
        return "string"
    return "any"


def _array_schema_to_ts(schema, depth):
    """Maps JSON Schema array to TS representation."""
    items = schema.get("items", {})
    item_type = json_schema_to_typescript(items, depth)
    if "\n" in item_type or " | " in item_type:
        return f"Array<{item_type}>"
    return f"{item_type}[]"


def _get_property_doc(prop_schema, indent):
    """Builds doc comments for a property schema."""
    doc_lines = []
    if "description" in prop_schema:
        for line in prop_schema["description"].strip().split("\n"):
            doc_lines.append(f"{indent}  * {line}")
    if "example" in prop_schema:
        ex_str = json.dumps(prop_schema["example"])
        doc_lines.append(f"{indent}  * @example {ex_str}")
    if doc_lines:
        return f"\n{indent}  /**\n" + "\n".join(doc_lines) + f"\n{indent}   */\n"
    return ""


def _object_schema_to_ts(schema, depth):
    """Maps JSON Schema object to TS representation."""
    properties = schema.get("properties", {})
    required = schema.get("required", [])
    if not properties:
        return "{}"

    indent = "  " * depth
    lines = ["{"]
    for prop, prop_schema in properties.items():
        if not isinstance(prop_schema, dict):
            continue
        doc = _get_property_doc(prop_schema, indent)
        opt = "" if prop in required else "?"
        val_type = json_schema_to_typescript(prop_schema, depth + 1)
        lines.append(f"{doc}{indent}  {prop}{opt}: {val_type};")
    lines.append(f"{indent}}}")
    return "\n".join(lines)


def _process_parameters(details, lines):
    """Formats path and query parameters into lines list."""
    params = details.get("parameters", [])
    path_params = [p for p in params if p.get("in") == "path"]
    query_params = [p for p in params if p.get("in") == "query"]

    if path_params:
        lines.append("**Path Parameters:**")
        for p in path_params:
            p_type = json_schema_to_typescript(p.get("schema", {}))
            p_desc = p.get("description", "").strip()
            lines.append(f"- `{p['name']}` (Required): `{p_type}` - {p_desc}")
    if query_params:
        lines.append("**Query Parameters:**")
        for p in query_params:
            req = " (Required)" if p.get("required") else ""
            p_type = json_schema_to_typescript(p.get("schema", {}))
            p_desc = p.get("description", "").strip()
            lines.append(f"- `{p['name']}`{req}: `{p_type}` - {p_desc}")


def _process_request_body(details, lines):
    """Formats the request body into lines list."""
    req_body = details.get("requestBody", {})
    if not req_body:
        return
    json_content = req_body.get("content", {}).get("application/json", {})
    if "schema" in json_content:
        ts_type = json_schema_to_typescript(json_content["schema"])
        lines.append(f"**Request Body (JSON):**\n```typescript\n{ts_type}\n```")


def _process_responses(details, lines):
    """Formats response definitions into lines list."""
    responses = details.get("responses", {})
    if not responses:
        return
    lines.append("**Responses:**")
    for code, resp in responses.items():
        desc = resp.get("description", "").strip()
        lines.append(f"- **{code}**: {desc}")
        json_content = resp.get("content", {}).get("application/json", {})
        if "schema" in json_content:
            ts_type = json_schema_to_typescript(json_content["schema"], 1)
            lines.append(f"  ```typescript\n  {ts_type}\n  ```")


def openapi_to_text(api_data):
    """Transforms a parsed OpenAPI definition into dense Markdown routes."""
    lines = []
    paths = api_data.get("paths", {})
    for path, methods in paths.items():
        for method, details in methods.items():
            lines.append(f"\n### {method.upper()} {path}")
            if "summary" in details:
                lines.append(f"**Summary:** {details['summary']}")
            if "description" in details:
                lines.append(details["description"].strip())

            _process_parameters(details, lines)
            _process_request_body(details, lines)
            _process_responses(details, lines)
    return "\n".join(lines)


def process_shortcodes(content):
    """Scans and replaces Hugo shortcodes with dense inline definitions."""

    def replace_http_api(match):
        spec, api = match.group(1), match.group(2)
        path = os.path.join(DATA_DIR, "api", spec, f"{api}.yaml")
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
            data = resolve_refs(data, os.path.dirname(path))
            data = resolve_all_of(data)
            return openapi_to_text(data)
        return f"*(API definition {spec}/{api} missing)*"

    def replace_event(match):
        event_name = match.group(1)
        path = os.path.join(DATA_DIR, "event-schemas", "schema", f"{event_name}.yaml")
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
            data = resolve_refs(data, os.path.dirname(path))
            data = resolve_all_of(data)
            ts = json_schema_to_typescript(data)
            ts_name = event_name.replace(".", "_")
            return (
                f"\n### Event `{event_name}`\n"
                f"```typescript\n"
                f"type {ts_name} = {ts};\n"
                f"```\n"
            )
        return f"*(Event definition {event_name} missing)*"

    def replace_definition(match):
        definition_path = match.group(1)
        path = os.path.join(DATA_DIR, f"{definition_path}.yaml")
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f)
            data = resolve_refs(data, os.path.dirname(path))
            data = resolve_all_of(data)
            title = data.get("title", definition_path.split("/")[-1])
            ts = json_schema_to_typescript(data)
            ts_name = title.replace(" ", "")
            return (
                f"\n### Definition `{title}`\n"
                f"```typescript\n"
                f"type {ts_name} = {ts};\n"
                f"```\n"
            )
        return f"*(Definition {definition_path} missing)*"

    # Replace shortcodes using regex
    content = re.sub(
        r'\{\{% http-api spec="([^"]+)" api="([^"]+)" %\}\}',
        replace_http_api,
        content,
    )
    content = re.sub(r'\{\{% event event="([^"]+)" %\}\}', replace_event, content)
    content = re.sub(
        r'\{\{% definition path="([^"]+)" %\}\}', replace_definition, content
    )

    # Strip added-in and changed-in tags
    content = re.sub(r'\{\{% added-in v="([^"]+)" %\}\}', r"*(Added in v\1)*", content)
    content = re.sub(
        r'\{\{% changed-in v="([^"]+)" %\}\}', r"*(Changed in v\1)*", content
    )
    content = re.sub(r"\{\{% boxes/[a-z]+ %\}\}", "\n> **Note:** ", content)
    content = re.sub(r"\{\{% /boxes/[a-z]+ %\}\}", "\n", content)
    return content


def _strip_front_matter(content):
    """Remove one leading YAML front-matter block, if present."""
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            return parts[2]
    return content


def _rel_output_path(src_path, source_root):
    """Map a source markdown file to its output .txt path."""
    rel_path = src_path.relative_to(source_root)
    if src_path.name == "_index.md":
        return rel_path.with_name("index.txt")
    return rel_path.with_suffix(".txt")


def _render_markdown_file(src_path):
    """Convert a Markdown source file to compact plain text."""
    with open(src_path, "r", encoding="utf-8") as f:
        content = f.read()

    content = _strip_front_matter(content)
    processed = process_shortcodes(content)
    processed = re.sub(r"[ \t]+$", "", processed, flags=re.MULTILINE)
    return re.sub(r"\n{3,}", "\n\n", processed)


def generate_spec_tree(source_roots=None, output_root=DEFAULT_OUTPUT_ROOT):
    """Traverse markdown source roots and generate a mirrored text tree."""
    roots = [Path(root) for root in (source_roots or DEFAULT_SOURCE_ROOTS)]
    output_root = Path(output_root)

    print("Generating mirrored plain-text Matrix Spec tree...")
    written = 0

    for source_root in roots:
        if not source_root.exists():
            continue

        for src_path in source_root.rglob("*.md"):
            rel_output_path = _rel_output_path(src_path, source_root)
            if source_root.name == "content":
                dest_path = output_root / rel_output_path
            else:
                dest_path = output_root / source_root.name / rel_output_path

            if dest_path.resolve() == src_path.resolve():
                continue

            processed = _render_markdown_file(src_path)

            dest_path.parent.mkdir(parents=True, exist_ok=True)
            with open(dest_path, "w", encoding="utf-8") as out:
                out.write(processed)
            written += 1

    print(f"Success! Wrote {written} generated text files under ./{output_root}/")


def _parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-root",
        default=str(DEFAULT_OUTPUT_ROOT),
        help="Destination root for generated text files.",
    )
    parser.add_argument(
        "--source-root",
        action="append",
        dest="source_roots",
        help="Markdown source root to process. Can be passed multiple times.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    generate_spec_tree(args.source_roots, args.output_root)
