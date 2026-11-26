#!/usr/bin/env python3
"""Judges the self-test of the real Laserdot+ app (report.json).

usage: check-selftest.py REPORT.json DRIVE_MOUNT MAC_DATA_DIR
"""
import json
import os
import sys

report_path, drive, mac_data = sys.argv[1], sys.argv[2], sys.argv[3]
r = json.load(open(report_path))
failures = []


def check(ok, what):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


check(r.get("error") == "", f"the self-test ran to the end (error {r.get('error')!r})")
check(r.get("network_denied") is True, "the engine runs with the network denied by macOS")
check(r.get("all_count", 0) >= 8, f"every file shows with nothing typed (got {r.get('all_count')})")
check("kind" in r.get("groups", []), f"the filter sidebar offers kinds (got {r.get('groups')})")
check(r.get("typed") == ["Trips", "beach trip.jpg", "paris trip.txt", "rome trip.txt"], f"typing narrows by name, folders included (got {r.get('typed')})")
check(r.get("filtered_kinds") == ["image"], f"ticking Pictures shows only pictures (got {r.get('filtered_kinds')})")
check("kind:image" in r.get("filtered_query", ""), f"the tick becomes a filter (got {r.get('filtered_query')!r})")
check("video" in r.get("details_sections", []) and "general" in r.get("details_sections", []),
      f"the details panel describes the video (got {r.get('details_sections')})")
check(r.get("trashed") is True and r.get("trash_hidden") is True, "Move to Trash moves the file and drops it from the list")
check(r.get("restored") is True, "Undo puts it back")
check(r.get("marquee_count", 0) >= 2, f"the selection box over the grid's tiles selects what it touches (got {r.get('marquee_count')})")
check(r.get("choices_arranged") is True, "all the choices: what can be chosen comes first in each group")
check(r.get("dupes_groups", 0) >= 1, f"Find Duplicates finds the same picture at several sizes (got {r.get('dupes_groups')} groups, problem {r.get('dupes_problem')!r})")
check("private" not in r.get("friendly_path", "private") and r.get("friendly_path", "").endswith("rome trip.txt"), f"paths read like Finder's (got {r.get('friendly_path')!r})")
check(r.get("drive_delete") is True, f"a file deleted on the exFAT drive outside Laserdot+ leaves the list (listed {r.get('drive_listed')})")
check(r.get("place_pill") == "This Mac", f"the chosen place is a pill in the search box (got {r.get('place_pill')!r})")
check(r.get("this_mac_count", 0) >= 1, f"This Mac shows this Mac's files (got {r.get('this_mac_count')})")
check("LDPlus" in r.get("drives", []), f"the plugged-in drive is listed (got {r.get('drives')})")
check(r.get("tray_count") == 1 and r.get("review_index") == 2, f"review mode: T marks one for the tray, K keeps (got {r.get('tray_count')}, {r.get('review_index')})")
check(r.get("external_listed") is True and r.get("external_delete") is True,
      "a file deleted outside Laserdot+ (as in Finder) leaves the list by itself")
check(r.get("select_all") is True, "Select All selects every file of the place")
check(len(r.get("months", [])) >= 1, f"the timeline groups files by month (got {r.get('months')})")
for s in ("list", "filtered", "grid", "sheet", "timeline", "details", "review", "tray", "place", "marquee", "duplicates"):
    check(s in r.get("screenshots", []), f"screenshot {s} taken")

# Privacy, checked on the real Mac: the drive's index is on the drive, and
# nothing in this Mac's data folder names the drive's file.
check(os.path.isdir(os.path.join(drive, ".laserdot")), "the drive's index is on the drive (.laserdot)")
leaks = []
for root, _, files in os.walk(mac_data):
    for f in files:
        p = os.path.join(root, f)
        try:
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"holiday.webm" in data or b"holiday" in data and b"LDPlus" in data:
            leaks.append(os.path.relpath(p, mac_data))
check(not leaks, f"nothing on this Mac names the drive's files (found in {leaks})")

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
