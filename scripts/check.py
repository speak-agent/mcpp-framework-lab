#!/usr/bin/env python3
"""Assertions over the records a build leaves and `mcpp why` prints.

    check.py record [--only-classes managed,pinned] [--entry SUBJECT ...]
    check.py why FILE [--entry SUBJECT ...]

`record` reads the newest target/*/*/resolution.json under the current
directory. `why` reads the JSON that `mcpp why sources --format json` printed
and checks its envelope first: kind `mcpp.why.sources`, topic `sources` and
status `ok`.

Each `--entry SUBJECT` selects one source by its subject, and the options that
follow it (--class, --origin-kind, --origin-line, --origin-key, --considered)
are the assertions about that entry. The script prints every entry it read and
exits 1 with the first assertion that does not hold.
"""
import glob
import json
import os
import sys


def fail(message):
    print("CHECK FAILED: " + message)
    sys.exit(1)


def show(entries, where):
    print("record: %s (%d entries)" % (where, len(entries)))
    for e in entries:
        o = e.get("origin", {})
        print("  %s" % e.get("subject"))
        print("    value:      %s" % e.get("value"))
        print("    class:      %s" % e.get("class"))
        print("    origin:     kind=%s file=%s line=%s key=%s" % (
            o.get("kind"), o.get("file"), o.get("line"), o.get("key")))
        print("    decidedFor: %s" % e.get("decidedFor"))
        for c in e.get("considered", []):
            print("    considered: %s" % c)


def load_record():
    paths = sorted(glob.glob("target/*/*/resolution.json"), key=os.path.getmtime)
    if not paths:
        fail("no target/*/*/resolution.json under " + os.getcwd())
    path = paths[-1]
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    if "sources" not in doc:
        fail("%s has no `sources` key; its keys are %s" % (path, sorted(doc)))
    return path, doc["sources"]


def load_why(path):
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    if doc.get("kind") != "mcpp.why.sources":
        fail("kind is %r, not 'mcpp.why.sources'" % doc.get("kind"))
    data = doc.get("data", {})
    if data.get("topic") != "sources":
        fail("data.topic is %r, not 'sources'" % data.get("topic"))
    if data.get("status") != "ok":
        fail("data.status is %r (reason %r), not 'ok'" % (data.get("status"), data.get("reason")))
    return path, data.get("sources", [])


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] not in ("record", "why"):
        fail("usage: check.py record|why [FILE] [--only-classes a,b] [--entry SUBJECT [--class C ...]]")

    class args:  # the parsed command line, by hand: the per-entry options repeat
        mode = argv[0]
        file = None
        only_classes = ""

    rest = argv[1:]
    if args.mode == "why":
        if not rest or rest[0].startswith("--"):
            fail("why needs the JSON file")
        args.file, rest = rest[0], rest[1:]

    wanted = []
    i = 0
    while i < len(rest):
        opt = rest[i]
        if i + 1 >= len(rest):
            fail("%s needs a value" % opt)
        if opt == "--only-classes":
            args.only_classes = rest[i + 1]
        elif opt == "--entry":
            wanted.append({"subject": rest[i + 1], "checks": []})
        elif opt in ("--class", "--origin-kind", "--origin-line", "--origin-key", "--considered"):
            if not wanted:
                fail("%s comes before any --entry" % opt)
            wanted[-1]["checks"].append((opt[2:], rest[i + 1]))
        else:
            fail("unknown option " + opt)
        i += 2

    if args.mode == "record":
        where, entries = load_record()
    else:
        if not args.file:
            fail("why needs the JSON file")
        where, entries = load_why(args.file)
    show(entries, where)

    if args.only_classes:
        allowed = set(args.only_classes.split(","))
        if not entries:
            fail("the record has no entries, so no class was checked")
        for e in entries:
            if e.get("class") not in allowed:
                fail("%s has class %r; the classes allowed here are %s"
                     % (e.get("subject"), e.get("class"), sorted(allowed)))

    for w in wanted:
        found = [e for e in entries if e.get("subject") == w["subject"]]
        if not found:
            fail("no entry for %s; the subjects are %s" % (w["subject"], [e.get("subject") for e in entries]))
        e = found[0]
        o = e.get("origin", {})
        for name, expected in w["checks"]:
            if name == "class":
                actual = e.get("class")
            elif name == "origin-kind":
                actual = o.get("kind")
            elif name == "origin-line":
                actual = str(o.get("line"))
            elif name == "origin-key":
                actual = o.get("key")
            elif name == "considered":
                if not any(expected in c for c in e.get("considered", [])):
                    fail("%s: no `considered` line contains %r; they are %s"
                         % (w["subject"], expected, e.get("considered")))
                continue
            if actual != expected:
                fail("%s: %s is %r, not %r" % (w["subject"], name, actual, expected))
    print("CHECK OK")


if __name__ == "__main__":
    main()
