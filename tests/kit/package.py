"""Builds the release zip by hand, the way BigWigs' packager would (see .pkgmeta), for uploading to
CurseForge and Wago yourself: the addon's files inside an OnAir/ folder. What goes in: every file git
has or would add (not the ignored ones), without dot files and the folders .pkgmeta ignores. Before
writing, it checks the TOC loads only files that are there, its icon is there, and the changelog's
newest version is the TOC's. It says so when a file in the zip isn't committed yet.

python tests/kit/package.py   (writes dist/OnAir-<version>.zip)
"""
import os
import re
import subprocess
import sys
import time
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, text=True,
                          encoding="utf-8").stdout


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8-sig") as f:
        return f.read()


def pkgmeta():
    """package-as and the ignore list (the two .pkgmeta keys this addon uses)."""
    name, ignore, in_ignore = None, [], False
    for line in read(".pkgmeta").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            in_ignore = line.startswith("ignore:")
            if line.startswith("package-as:"):
                name = line.split(":", 1)[1].strip()
        elif in_ignore and line.strip().startswith("- "):
            ignore.append(line.strip()[2:].strip().rstrip("/"))
    return name, ignore


def shipped(ignore):
    files = git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split("\0")
    keep = []
    for path in sorted(p for p in files if p and os.path.isfile(os.path.join(ROOT, p))):
        if any(part.startswith(".") for part in path.split("/")):
            continue
        if any(path == ig or path.startswith(ig + "/") for ig in ignore):
            continue
        keep.append(path)
    return keep


def problems_in(name, files):
    problems = []
    toc_path = name + ".toc"
    if toc_path not in files:
        return ["no " + toc_path], None
    toc = read(toc_path)
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    version = version and version.group(1)
    if not version:
        problems.append("the TOC has no ## Version")
    for line in toc.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and line.replace("\\", "/") not in files:
            problems.append("the TOC loads " + line + ", which isn't in the zip")
    icon = re.search(r"^## IconTexture:\s*(\S+)", toc, re.M)
    if icon:
        rel = icon.group(1).replace("\\", "/").split("/AddOns/" + name + "/", 1)[-1]
        if not any(f == rel or f.startswith(rel + ".") for f in files):
            problems.append("the TOC's icon isn't in the zip: " + icon.group(1))
    newest = re.search(r"^## (\S+)", read("CHANGELOG.md"), re.M) if "CHANGELOG.md" in files else None
    if not newest or newest.group(1) != version:
        problems.append(f"the changelog's newest version ({newest and newest.group(1)}) isn't the TOC's ({version})")
    return problems, version


def main():
    name, ignore = pkgmeta()
    files = shipped(ignore)
    problems, version = problems_in(name, files)
    if problems:
        print("not packaged:")
        for p in problems:
            print("  " + p)
        sys.exit(1)
    pending = [line[3:] for line in git("status", "--porcelain", "--", *files).splitlines()]
    if pending:
        print("note: not committed yet (the zip has them as they are now):")
        for p in pending:
            print("  " + p)
    # The same time on every file (the last commit's): the same files make the same zip.
    stamp = time.localtime(int(git("log", "-1", "--format=%ct").strip() or time.time()))[:6]
    out = os.path.join(ROOT, "dist", f"{name}-{version}.zip")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    folders = set()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for path in files:
            parts = path.split("/")
            for i in range(len(parts)):
                folder = "/".join([name] + parts[:i]) + "/"
                if folder not in folders:
                    folders.add(folder)
                    z.writestr(zipfile.ZipInfo(folder, stamp), b"")
            info = zipfile.ZipInfo(f"{name}/{path}", stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(os.path.join(ROOT, path), "rb") as f:
                z.writestr(info, f.read())
    with zipfile.ZipFile(out) as z:
        bad = z.testzip()
        if bad:
            sys.exit("broken entry in the zip: " + bad)
    print(f"wrote {out}: {len(files)} files, {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
