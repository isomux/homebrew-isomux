#!/usr/bin/env python3
"""Point Formula/isomux.rb at an isomux release.

Usage: bump.py [TAG]. Without TAG, the latest release of nmamano/isomux.
Rewrites the url, sha256, COMMIT and the bun resource, and prints the tag.
Prints nothing and leaves the file alone when the formula already has it.
"""
import hashlib
import json
import os
import re
import sys
import urllib.request

REPO = "nmamano/isomux"
FORMULA = os.path.join(os.path.dirname(__file__), "..", "..", "Formula", "isomux.rb")
TAG_RE = re.compile(r"^v\d{4}\.\d{1,2}\.\d{1,2}(\.\d+)?$")


def fetch(url, api=False):
    headers = {"User-Agent": "isomux-homebrew-bump"}
    token = os.environ.get("GH_TOKEN")
    if api:
        headers["Accept"] = "application/vnd.github+json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as r:
        return r.read()


def api(path):
    return json.loads(fetch(f"https://api.github.com/repos/{REPO}/{path}", api=True))


def sha256(url):
    return hashlib.sha256(fetch(url)).hexdigest()


def replace_once(text, pattern, value):
    new, count = re.subn(pattern, lambda m: m.group(1) + value + m.group(2), text)
    if count != 1:
        sys.exit(f"bump: expected one match for {pattern!r}, found {count}")
    return new


def numeric(tag):
    return [int(part) for part in tag[1:].split(".")]


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else api("releases/latest")["tag_name"]
    if not TAG_RE.match(tag):
        sys.exit(f"bump: {tag!r} is not a release tag")
    with open(FORMULA) as f:
        formula = f.read()
    current = re.search(r'/refs/tags/(v[0-9.]+)\.tar\.gz"', formula).group(1)
    if numeric(tag) <= numeric(current):
        return

    tarball = f"https://github.com/{REPO}/archive/refs/tags/{tag}.tar.gz"
    commit = api(f"commits/{tag}")["sha"]
    package = json.loads(fetch(f"https://raw.githubusercontent.com/{REPO}/{tag}/package.json"))
    match = re.fullmatch(r"bun@(\d+\.\d+\.\d+)", package.get("packageManager", ""))
    if not match:
        sys.exit("bump: package.json pins no bun version in packageManager")
    bun = match.group(1)
    bun_url = f"https://github.com/oven-sh/bun/releases/download/bun-v{bun}/bun-darwin-{{}}.zip"

    formula = replace_once(formula, r'(\n  url ")[^"]+(")', tarball)
    formula = replace_once(formula, r'(\n  sha256 ")[0-9a-f]{64}(")', sha256(tarball))
    formula = replace_once(formula, r'(COMMIT = ")[0-9a-f]{40}(")', commit)
    for arch in ("aarch64", "x64"):
        url = bun_url.format(arch)
        formula = replace_once(
            formula,
            r'(\n      url ")[^"]+/bun-darwin-' + arch + r'\.zip(")',
            url,
        )
        formula = replace_once(
            formula,
            r'(bun-darwin-' + arch + r'\.zip"\n      sha256 ")[0-9a-f]{64}(")',
            sha256(url),
        )
    with open(FORMULA, "w") as f:
        f.write(formula)
    print(tag)


if __name__ == "__main__":
    main()
