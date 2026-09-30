#!/usr/bin/env python3
# Re-upload using git-normalised blob content so the remote tree matches the
# local index byte-for-byte, then mirror the resulting commit locally.
import base64
import datetime as dt
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.request
from pathlib import Path

BASE = Path(r"Z:\软件\software\workbuddy - Inter\新建文件夹 (3)")
TOKEN = Path(r"C:\Users\MECHREVO\WorkBuddy\2026-09-16-18-38-30\.gh_pat").read_text(encoding="utf-8").strip()
API = "https://api.github.com/repos/icecream68587-ship-it/workbuddy"
MSG = "Initial commit: WorkBuddy"
AUTHOR_NAME, AUTHOR_EMAIL = "icecream68587-ship-it", "icecream68587@gmail.com"
DATE_ISO = "2026-09-29T17:00:44Z"


def git(*args, binary=False):
    r = subprocess.run(["git", *args], cwd=BASE, capture_output=True, check=True)
    return r.stdout if binary else r.stdout.decode("utf-8")


def api(method, url, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "workbuddy-uploader")
    with urllib.request.urlopen(req, context=ssl.create_default_context()) as r:
        return json.loads(r.read().decode("utf-8") or "{}")


# index entries: "<mode> <sha> <stage>\t<path>"
entries = []
for rec in git("ls-files", "-s", "-z").split("\x00"):
    if not rec:
        continue
    meta, path = rec.split("\t", 1)
    mode, sha, _stage = meta.split()
    content = subprocess.run(["git", "cat-file", "blob", sha], cwd=BASE,
                             capture_output=True, check=True).stdout
    blob = api("POST", f"{API}/git/blobs",
               {"content": base64.b64encode(content).decode(), "encoding": "base64"})
    entries.append({"path": path, "mode": mode.zfill(6), "type": "blob", "sha": blob["sha"]})
    print(f"  {path} {mode.zfill(6)} {len(content)}B -> {blob['sha'][:8]}")

local_tree = git("rev-parse", "HEAD^{tree}").strip()
tree = api("POST", f"{API}/git/trees", {"tree": entries})
print(f"tree   remote={tree['sha']} local={local_tree}")
assert tree["sha"] == local_tree, "tree mismatch"

commit = api("POST", f"{API}/git/commits", {
    "message": MSG,
    "tree": tree["sha"],
    "parents": [],
    "author": {"name": AUTHOR_NAME, "email": AUTHOR_EMAIL, "date": DATE_ISO},
    "committer": {"name": AUTHOR_NAME, "email": AUTHOR_EMAIL, "date": DATE_ISO},
})
print(f"commit remote={commit['sha']}")

api("PATCH", f"{API}/git/refs/heads/main", {"sha": commit["sha"], "force": True})
print("main ->", commit["sha"])

# mirror the same commit object locally -> identical sha if bytes match
epoch = int(dt.datetime.strptime(DATE_ISO, "%Y-%m-%dT%H:%M:%SZ")
            .replace(tzinfo=dt.timezone.utc).timestamp())
env = dict(os.environ,
           GIT_AUTHOR_NAME=AUTHOR_NAME, GIT_AUTHOR_EMAIL=AUTHOR_EMAIL,
           GIT_AUTHOR_DATE=f"@ {epoch} +0000",
           GIT_COMMITTER_NAME=AUTHOR_NAME, GIT_COMMITTER_EMAIL=AUTHOR_EMAIL,
           GIT_COMMITTER_DATE=f"@ {epoch} +0000")
r = subprocess.run(["git", "commit-tree", local_tree, "-m", MSG],
                   cwd=BASE, capture_output=True, env=env, check=True)
local_sha = r.stdout.decode().strip()
print(f"commit local ={local_sha}")
print("MATCH" if local_sha == commit["sha"] else "MISMATCH")
