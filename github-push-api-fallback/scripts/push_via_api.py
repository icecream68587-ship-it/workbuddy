#!/usr/bin/env python3
"""Push a git repo to GitHub over the REST API, for when git's own transport is blocked.

Pure standard library + git in PATH -> works on Windows / macOS / Linux.

Examples:
    # first upload to an empty remote repo
    python push_via_api.py owner/repo --token-file .gh_pat

    # later updates (fast-forward; only changed files are uploaded)
    python push_via_api.py owner/repo --token-file .gh_pat -m "Fix typo"

    # token from env, other dir/branch, skip local ref sync
    GH_TOKEN=ghp_xxx python push_via_api.py owner/repo --dir ../myproj --no-mirror
"""
import argparse
import base64
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.request

UA = "push-via-api/1.0"


def git(d, *args, binary=False):
    r = subprocess.run(["git", *args], cwd=d, capture_output=True, check=True)
    return r.stdout if binary else r.stdout.decode("utf-8")


def api(token, method, url, payload=None, allow_404=False):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", UA)
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context()) as r:
            return json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        if allow_404 and e.code == 404:
            return None
        print(f"HTTP {e.code} {method} {url}", file=sys.stderr)
        print(e.read().decode("utf-8", "replace"), file=sys.stderr)
        raise


def main() -> int:
    p = argparse.ArgumentParser(description="Push a repo to GitHub via the REST API.")
    p.add_argument("repo", help="owner/name")
    p.add_argument("--dir", default=".", help="local repo (default: cwd)")
    p.add_argument("--token-file", help="file containing the PAT")
    p.add_argument("--branch", default="main")
    p.add_argument("-m", "--message", default="Update")
    p.add_argument("--author", help='"Name <email>" (default: git config user)')
    p.add_argument("--no-mirror", action="store_true",
                   help="skip syncing local refs to the remote commit")
    a = p.parse_args()

    d = os.path.abspath(a.dir)
    token = (open(a.token_file).read().strip() if a.token_file
             else os.environ.get("GH_TOKEN", "")).strip()
    if not token:
        sys.exit("no token: pass --token-file or set GH_TOKEN")

    api_base = f"https://api.github.com/repos/{a.repo}"
    head_ref = f"{api_base}/git/refs/heads/{a.branch}"   # plural: PATCH 404s on /git/ref/

    # what is already on the remote?
    ref = api(token, "GET", head_ref, allow_404=True)
    if ref is None:
        # empty repo: the Git Data API refuses to work until it has one commit
        print("remote is empty -> seeding one placeholder commit")
        api(token, "PUT", f"{api_base}/contents/.init",
            {"message": "init", "content": base64.b64encode(b"init").decode()})
        ref = api(token, "GET", head_ref)
    parent = ref["object"]["sha"]
    print(f"remote head {parent[:8]}")

    local_tree = git(d, "write-tree").strip()

    # which paths changed since the remote head? (-z: one NUL-separated field
    # per record, so ask for add/modify and delete separately instead of
    # trying to parse "--name-status" pairs)
    known = subprocess.run(["git", "cat-file", "-e", parent + "^{commit}"],
                           cwd=d, capture_output=True).returncode == 0
    if known:
        upserts = [x.decode("utf-8") for x in git(
            d, "diff", "--diff-filter=ACMRT", "--name-only", "-z",
            parent, local_tree, binary=True).split(b"\x00") if x]
        deletes = [x.decode("utf-8") for x in git(
            d, "diff", "--diff-filter=D", "--name-only", "-z",
            parent, local_tree, binary=True).split(b"\x00") if x]
    else:
        upserts = [x.decode("utf-8") for x in git(
            d, "ls-files", "-z", binary=True).split(b"\x00") if x]
        deletes = []

    entries = [{"path": r, "mode": "100644", "type": "blob", "sha": None}
               for r in deletes]
    for r in deletes:
        print(f"  - {r}")

    for rel in upserts:
        idx = git(d, "rev-parse", f":{rel}").strip()
        mode = git(d, "ls-files", "-s", "--", rel).split()[0].zfill(6)
        # read from the index, NOT the working file: core.autocrlf would
        # otherwise upload CRLF while the index holds LF -> tree sha mismatch
        content = git(d, "cat-file", "blob", idx, binary=True)
        blob = api(token, "POST", f"{api_base}/git/blobs",
                   {"content": base64.b64encode(content).decode(),
                    "encoding": "base64"})
        entries.append({"path": rel, "mode": mode, "type": "blob", "sha": blob["sha"]})
        print(f"  {'+' if not known else '~'} {rel} {mode} {len(content)}B")

    if not entries:
        print("nothing to push")
        return 0

    remote_tree = api(token, "GET", f"{api_base}/commits/{a.branch}")["commit"]["tree"]["sha"]
    tree = api(token, "POST", f"{api_base}/git/trees",
               {"base_tree": remote_tree, "tree": entries})
    print(f"tree remote={tree['sha']} local={local_tree}")
    if tree["sha"] != local_tree:
        sys.exit("tree mismatch - aborting")

    who = a.author or (f"{git(d, 'config', 'user.name').strip()} "
                       f"<{git(d, 'config', 'user.email').strip()}>")
    name, email = who.rsplit("<", 1)
    epoch = int(time.time())
    stamp = {"name": name.strip(), "email": email.rstrip(">").strip(),
             "date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))}
    commit = api(token, "POST", f"{api_base}/git/commits",
                 {"message": a.message, "tree": tree["sha"], "parents": [parent],
                  "author": stamp, "committer": stamp})
    api(token, "PATCH", head_ref, {"sha": commit["sha"], "force": True})
    print(f"commit {commit['sha']} -> {a.repo}@{a.branch}")

    if a.no_mirror:
        return 0

    # reproduce the same commit object locally.
    # GitHub stores the message WITHOUT a trailing newline, unlike commit-tree.
    line = f"{stamp['name']} <{stamp['email']}> {epoch} +0000"
    body = (f"tree {local_tree}\nparent {parent}\n"
            f"author {line}\ncommitter {line}\n\n{a.message}").encode()
    out = subprocess.run(["git", "hash-object", "-t", "commit", "-w", "--stdin"],
                         cwd=d, input=body, capture_output=True, check=True)
    local_sha = out.stdout.decode().strip()
    ok = local_sha == commit["sha"]
    print(f"local commit {local_sha[:8]} {'MATCH' if ok else 'MISMATCH'}")
    if not ok:
        print("refs left untouched; remote is already updated")
        return 1
    git(d, "update-ref", f"refs/heads/{a.branch}", local_sha)
    remote_ref = os.path.join(d, ".git", "refs", "remotes", "origin", a.branch)
    os.makedirs(os.path.dirname(remote_ref), exist_ok=True)
    with open(remote_ref, "w") as fh:   # update-ref silently no-ops on some repos
        fh.write(local_sha + "\n")
    print(f"local {a.branch} and origin/{a.branch} -> {local_sha[:8]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
