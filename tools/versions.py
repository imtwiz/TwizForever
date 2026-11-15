#!/usr/bin/env python3
"""Version guard for the Twiz addons.

Checks GitHub first: fetches main and every other branch (contributors such as
LeetStick push their own), reads each addon's "## Version:" there, and makes
sure the version you're about to release is higher than all of them, so two
different builds never share a version number.

  python3 tools/versions.py            # report: local vs GitHub, flag problems
  python3 tools/versions.py --bump     # give every changed addon a new version
                                       # above anything on GitHub (patch +1)
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = sorted(p.parent.name for p in ROOT.glob("Twiz*/Twiz*.toc"))


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "0"))


def toc_version(text):
    m = re.search(r"^## Version:\s*(\S+)", text or "", re.M)
    return m.group(1) if m else None


def remote_refs():
    git("fetch", "-q", "origin", "+refs/heads/*:refs/remotes/origin/*")
    out = git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin").stdout.split()
    return [r for r in out if r != "origin/HEAD" and r != "origin"]


def remote_versions(addon, refs):
    found = {}
    for ref in refs:
        r = git("show", f"{ref}:{addon}/{addon}.toc")
        if r.returncode == 0:
            v = toc_version(r.stdout)
            if v:
                found[ref] = v
    return found


def changed_since_main(addon):
    r = git("diff", "--quiet", "origin/main", "--", addon)
    return r.returncode != 0


def main():
    bump = "--bump" in sys.argv
    refs = remote_refs()
    problems = 0
    for addon in ADDONS:
        toc = ROOT / addon / f"{addon}.toc"
        text = toc.read_text()
        local = toc_version(text)
        remote = remote_versions(addon, refs)
        highest = max([local] + list(remote.values()), key=vtuple)
        changed = changed_since_main(addon)
        clash = [ref for ref, v in remote.items() if vtuple(v) >= vtuple(local) and ref != "origin/main"]
        stale = changed and vtuple(local) <= vtuple(remote.get("origin/main", "0"))
        status = "ok"
        if changed and (clash or stale):
            status = "NEEDS A NEW VERSION"
            problems += 1
            if bump:
                parts = list(vtuple(highest)) + [0, 0, 0]
                new = f"{parts[0]}.{parts[1]}.{parts[2] + 1}"
                toc.write_text(re.sub(r"^## Version:\s*\S+", f"## Version: {new}", text, count=1, flags=re.M))
                status = f"bumped to {new}"
                problems -= 1
        others = ", ".join(f"{ref.replace('origin/', '')} {v}" for ref, v in sorted(remote.items()))
        print(f"{addon:10} local {local:8} {'(changed)' if changed else '         '}  github: {others}  -> {status}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
