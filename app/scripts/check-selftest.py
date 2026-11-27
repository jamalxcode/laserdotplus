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
check({"dates.created", "dates.modified"} <= set(r.get("dates_keys", [])), f"the file's created and modified dates are read (got {r.get('dates_keys')})")
check(r.get("details_sections", [None])[0] == "dates", f"the details panel starts with the file's dates (got {r.get('details_sections')})")
check("video" in r.get("details_sections", []) and "general" in r.get("details_sections", []),
      f"the details panel describes the video (got {r.get('details_sections')})")
check(r.get("trashed") is True and r.get("trash_hidden") is True, "Move to Trash moves the file and drops it from the list")
check(r.get("restored") is True, "Undo puts it back")
check(r.get("clicks") == [True, True, True], f"a click selects one, ⌘-click adds one and takes it out again (got {r.get('clicks')})")
check(r.get("view_on_drive") is True, "a drive's saved view is kept on the drive, not on this Mac")
check(r.get("space_items", 0) > 0, f"Clean Up ▸ Space lists the folders by size (got {r.get('space_items')})")
check(r.get("scale_indexed") is True and r.get("scale_files", 0) >= 40000, f"40,000 files are indexed (got {r.get('scale_files')})")
check(r.get("scale_junk", 0) >= 20000, f"Junk lists tens of thousands of finds (got {r.get('scale_junk')})")
check(r.get("scale_selected", 0) >= 40000, f"Select All selects all 40,000 (got {r.get('scale_selected')})")
check(r.get("scale_longest_stall", 99) < 2.0, f"the window never stalls for 2 s at 40,000 files (longest {r.get('scale_longest_stall')} s in {r.get('scale_stall_step')!r})")
check(r.get("scale_memory_mb", 9999) < 1536, f"memory stays under 1.5 GB (got {r.get('scale_memory_mb')} MB)")
check(r.get("broken_ran") is True, "Clean Up ▸ Broken looks through the index")
check(r.get("checksums_saved", 0) > 0 and r.get("checksums_damage") == 0 and r.get("checksums_on_drive") is True,
      f"the drive's fingerprints are saved on it and checked without damage (got {r.get('checksums_saved')}, {r.get('checksums_damage')})")
check(r.get("inspector_shown") is True, "the inspector stays on (Review and Clean Up hide it only while they show)")
check(r.get("window_click") is True, "a click delivered by the window reaches the file under it")
check(r.get("window_cmd_click") == 2, f"a ⌘-click delivered by the window adds a file, and the pointer moving on keeps both (got {r.get('window_cmd_click')}, trace {r.get('selection_trace')})")
check(r.get("arrow_moves") is True, "→ moves the selection to the next file")
check(r.get("keep_oldest") is True, "Keep ▸ The Oldest Copy keeps one copy per group, the oldest")
check(r.get("double_click_opens_first") is True, "a double click opens the file its first click was on")
check(r.get("drag_box", 0) >= 2, f"dragging the mouse from empty space selects the tiles it crosses (got {r.get('drag_box')})")
check(r.get("marquee_count", 0) >= 2, f"the selection box over the grid's tiles selects what it touches (got {r.get('marquee_count')})")
check(r.get("choices_arranged") is True, "all the choices: what can be chosen comes first in each group")
check(r.get("dupes_groups", 0) >= 1, f"Find Duplicates finds the same picture at several sizes (got {r.get('dupes_groups')} groups, problem {r.get('dupes_problem')!r})")
check("private" not in r.get("friendly_path", "private") and r.get("friendly_path", "").endswith("rome trip.txt"), f"paths read like Finder's (got {r.get('friendly_path')!r})")
check(r.get("drive_delete") is True, f"a file deleted on the exFAT drive outside Laserdot+ leaves the list (listed {r.get('drive_listed')})")
names = r.get("sweep_names", [])
check("VID_2034.mp4" in names and "IMG_0001.png" in names and not any("trip" in n for n in names), f"What Is This? goes through the unclear names only (got {names})")
check(r.get("kind_colors") == 6, f"each kind has a colour of its own (got {r.get('kind_colors')})")
check(r.get("type_kinds") == ["video", "image", "document", "document", "audio", "archive"],
      f"file types take their kind's colour (got {r.get('type_kinds')})")
check(bool(r.get("sweep_suggestion")), f"a better name is suggested (got {r.get('sweep_suggestion')!r})")
check(set(r.get("junk_whys", [])) >= {"system", "partial", "empty_folder"}, f"Clean Up ▸ Junk finds system files, unfinished downloads and empty folders (got {r.get('junk_whys')})")
check(r.get("place_pill") == "This Mac", f"the chosen place is a pill in the search box (got {r.get('place_pill')!r})")
check(r.get("this_mac_count", 0) >= 1, f"This Mac shows this Mac's files (got {r.get('this_mac_count')})")
check("LDPlus" in r.get("drives", []), f"the plugged-in drive is listed (got {r.get('drives')})")
check(r.get("tray_count") == 1 and r.get("review_index") == 2, f"review mode: T marks one for the tray, K keeps (got {r.get('tray_count')}, {r.get('review_index')})")
check(r.get("external_listed") is True and r.get("external_delete") is True,
      "a file deleted outside Laserdot+ (as in Finder) leaves the list by itself")
check(r.get("select_all") is True, "Select All selects every file of the place")
check(len(r.get("months", [])) >= 1, f"the timeline groups files by month (got {r.get('months')})")
for s in ("list", "filtered", "grid", "sheet", "timeline", "details", "review", "tray", "place", "marquee", "duplicates", "sweep", "dark", "junk", "space"):
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
