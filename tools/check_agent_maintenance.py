#!/usr/bin/env python3
"""Enforce structural agent/skill synchronization in a Git change set."""

import argparse
import os
import re
import subprocess
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAINTENANCE_RE = re.compile(
    r"(^|/)AGENTS\.md$|\.agent\.md$|(^|/)SKILL\.md$", re.IGNORECASE
)
SKILL_RE = re.compile(r"(^|/)\.agents/skills/.+/SKILL\.md$|"
                      r"(^|/)\.github/skills/.+/SKILL\.md$|"
                      r"(^|/)\.claude/skills/.+/SKILL\.md$", re.IGNORECASE)
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
REQUIRED_AGENTS = (
    "Continuous Agent & Skills Maintenance",
    "Agent instructions and skills are living repository artifacts.",
    "Every repository modification MUST include an agent/skills synchronization step.",
    "Before completing any task, inspect the applicable AGENTS.md and SKILL.md files, update the affected instructions, and validate their consistency with the implementation.",
    "A code change without the corresponding agent knowledge maintenance is considered incomplete.",
    "Never claim completion when the synchronization step has been skipped or has failed.",
)


def git(*args, check=True):
    result = subprocess.run(["git", *args], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or "git command failed")
    return result


def changed_paths(base, head, worktree):
    paths = set()
    if worktree:
        result = git("status", "--porcelain=v1", "-z")
        entries = result.stdout.split("\0")
        for entry in entries:
            if entry:
                paths.add(entry[3:])
        return paths
    result = git("diff", "--name-only", "-z", base, head)
    paths.update(path for path in result.stdout.split("\0") if path)
    return paths


def instruction_diff(paths, base, head, worktree):
    relevant = sorted(path for path in paths if MAINTENANCE_RE.search(path))
    if not relevant:
        return relevant, 0
    if worktree:
        args = ["diff", "--no-ext-diff", "--unified=0", "HEAD", "--", *relevant]
        result = git(*args)
        diff = result.stdout
        # Untracked instruction files have no git diff yet; count their real content.
        for path in relevant:
            if os.path.isfile(os.path.join(ROOT, path)) and not git(
                    "ls-files", "--error-unmatch", path, check=False).returncode == 0:
                with open(os.path.join(ROOT, path), encoding="utf-8") as stream:
                    diff += "\n".join("+" + line for line in stream)
    else:
        diff = git("diff", "--no-ext-diff", "--unified=0", base, head,
                   "--", *relevant).stdout
    added = "\n".join(line[1:] for line in diff.splitlines()
                       if line.startswith("+") and not line.startswith("+++"))
    return relevant, len(re.sub(r"\s+", "", added))


def read_text(path):
    full_path = os.path.join(ROOT, path)
    if not os.path.isfile(full_path):
        return None
    with open(full_path, encoding="utf-8") as stream:
        return stream.read()


def validate_instructions(paths):
    errors = []
    all_paths = set()
    for parent, _dirs, files in os.walk(ROOT):
        if ".git" in parent.split(os.sep):
            continue
        for name in files:
            if name == "AGENTS.md" or name.endswith(".agent.md") or name == "SKILL.md":
                all_paths.add(os.path.relpath(os.path.join(parent, name), ROOT))
    for path in sorted(all_paths):
        text = read_text(path)
        if text is None:
            continue
        if path == "AGENTS.md" or path.endswith("/AGENTS.md"):
            for phrase in REQUIRED_AGENTS:
                if phrase not in text:
                    errors.append(f"{path}: missing required policy text: {phrase}")
            if "Post-Change Definition of Done" not in text:
                errors.append(f"{path}: missing Post-Change Definition of Done")
        if path.endswith(".agent.md"):
            if "Post-Change Knowledge Synchronization" not in text:
                errors.append(f"{path}: missing Post-Change Knowledge Synchronization")
        if SKILL_RE.search(path):
            frontmatter = re.match(r"\A---\n(.*?)\n---(?:\n|$)", text, re.DOTALL)
            if not frontmatter:
                errors.append(f"{path}: invalid or missing Agent Skills name frontmatter")
            else:
                metadata = frontmatter.group(1)
                if not re.search(r"(?m)^name:\s*\S+", metadata):
                    errors.append(f"{path}: missing Agent Skills name frontmatter")
                if not re.search(r"(?m)^description:\s*", metadata):
                    errors.append(f"{path}: missing Agent Skills description frontmatter")
            if "Maintenance & Continuous Learning" not in text:
                errors.append(f"{path}: missing Maintenance & Continuous Learning")
        for target in LINK_RE.findall(text):
            if target.startswith(("https://", "http://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0].split("?", 1)[0]
            if not target:
                continue
            destination = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not os.path.exists(os.path.join(ROOT, destination)):
                errors.append(f"{path}: broken local Markdown link: {target}")
    return errors


def run(base=None, head=None, worktree=False):
    paths = changed_paths(base, head, worktree)
    if not paths:
        print("Agent maintenance check: no changed paths found.", file=sys.stderr)
        return 1
    relevant, added_chars = instruction_diff(paths, base, head, worktree)
    project_paths = paths - set(relevant)
    if not relevant:
        print("Agent maintenance check failed: project changes must include a substantive update to AGENTS.md, a specialized *.agent.md, or SKILL.md.", file=sys.stderr)
        return 1
    if added_chars < 40:
        print("Agent maintenance check failed: maintenance files need at least 40 non-whitespace added characters; empty, whitespace-only, and trivial edits do not qualify.", file=sys.stderr)
        return 1
    errors = validate_instructions(paths)
    if errors:
        for error in errors:
            print(f"Agent maintenance check failed: {error}", file=sys.stderr)
        return 1
    print(f"Agent maintenance check passed: {len(paths)} changed paths; "
          f"{len(relevant)} instruction files changed; "
          f"{added_chars} substantive added characters. Structural checks passed; "
          "semantic relevance still requires review.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="base Git commit for a comparison")
    parser.add_argument("--head", help="head Git commit for a comparison")
    parser.add_argument("--worktree", action="store_true",
                        help="check staged, unstaged, and untracked local changes against HEAD")
    args = parser.parse_args()
    if ((args.worktree and (args.base or args.head)) or
            (not args.worktree and not (args.base and args.head)) or
            bool(args.base) != bool(args.head)):
        parser.error("choose either --worktree or both --base and --head")
    try:
        return run(args.base, args.head, args.worktree)
    except (OSError, RuntimeError) as error:
        print(f"Agent maintenance check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
