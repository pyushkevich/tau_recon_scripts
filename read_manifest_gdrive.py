import gspread
from gspread.utils import absolute_range_name, fill_gaps, numericise_all, to_records
import argparse
import csv
import json
import os
import re
import sys
import tempfile
import time

# Name of the spreadsheet on Google Drive
SPREADSHEET = "HistologyMatching"

# Columns written to the output CSV (all must be present in the worksheet)
COLUMNS = ['Slide', 'Stain', 'Block', 'Section', 'Slice', 'Certainty', 'Tags']

# Name of the cache file inside the cache directory
CACHE_FILE = "worksheets.json"

# Create a parser
parse = argparse.ArgumentParser(
    description="Download HistologyMatching sheet from GDrive")

# Add the arguments
parse.add_argument('--json', '-j', metavar='json', type=str,
                   help="Credentials JSON file for service account")

parse.add_argument('--cache', '-c', metavar='dir', type=str,
                   help="Directory where all worksheets are cached. If the cache is "
                        "missing or stale, all worksheets are downloaded in one request")

parse.add_argument('--max-age', '-a', metavar='seconds', type=float, default=600,
                   help="Maximum age of the cache in seconds before it is refreshed "
                        "(default: 600)")

parse.add_argument('id', metavar='specimen_id', type=str,
                   help='ID of the specimen you want to extract from the sheet')

parse.add_argument('csv', metavar='csv', type=str,
                   help='Output CSV file')


def fetch_all_worksheets(json_key):
    """Download every worksheet of the spreadsheet with a single batch request.
    Returns a dict {worksheet title: list of rows}, rows being lists of strings."""
    gc = gspread.service_account(filename=json_key)
    sh = gc.open(SPREADSHEET)
    titles = [ws.title for ws in sh.worksheets()]
    resp = sh.values_batch_get([absolute_range_name(t) for t in titles])
    value_ranges = resp.get('valueRanges', [])
    if len(value_ranges) != len(titles):
        raise RuntimeError("Batch request returned {} ranges for {} worksheets".format(
            len(value_ranges), len(titles)))
    return {t: vr.get('values', []) for t, vr in zip(titles, value_ranges)}


def load_worksheets(json_key, cache_dir, max_age):
    """Return all worksheets, from the cache if it is fresh enough."""
    if not cache_dir:
        return fetch_all_worksheets(json_key)

    fn = os.path.join(cache_dir, CACHE_FILE)
    try:
        if time.time() - os.path.getmtime(fn) < max_age:
            with open(fn) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass

    # Refresh the cache. Write to a temp file and rename, so that concurrent
    # readers never see a partially written cache
    data = fetch_all_worksheets(json_key)
    os.makedirs(cache_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=cache_dir, suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f)
        umask = os.umask(0)
        os.umask(umask)
        os.chmod(tmp, 0o666 & ~umask)
        os.replace(tmp, fn)
    except BaseException:
        os.unlink(tmp)
        raise
    return data


def worksheet_records(rows):
    """Same output as gspread's Worksheet.get_all_records() for these rows."""
    if not rows:
        return []
    rows = fill_gaps(rows)
    return to_records(rows[0], [numericise_all(r) for r in rows[1:]])


def to_int(x):
    """Integer value of a cell, or '' if it is blank or not an integer."""
    try:
        f = float(x)
    except (TypeError, ValueError):
        return ''
    return int(f) if f.is_integer() else ''


def clean_text(x):
    """Free-text columns must not contain commas or quotes, since the shell
    scripts parse the CSV by splitting on commas. Multiple tags become
    semicolon-separated, e.g. "good, rescan" -> "good;rescan"."""
    return re.sub(r'\s*[,;"\r\n]+\s*', ';', str(x)).strip('; ')


# Parse the arguments
args = parse.parse_args()

# Load all the worksheets (from cache or from Google Sheets)
sheets = load_worksheets(args.json, args.cache, args.max_age)

# Find the worksheet that matches our ID
match = [ t for t in sheets if t.split('_')[0] == args.id ]
if len(match) != 1:
    match = [ t for t in sheets if t.startswith(args.id) ]
    if len(match) != 1:
        print("No matches or multiple matches for ID {}: {}".format(args.id, match))
        sys.exit(255)

# Extract the worksheet
recs = worksheet_records(sheets[match[0]])

missing = [c for c in COLUMNS if recs and c not in recs[0]]
if missing:
    print("Worksheet {} is missing columns {}".format(match[0], missing))
    sys.exit(255)

# Write to CSV
with open(args.csv, 'w', newline='') as f:
    w = csv.writer(f, lineterminator='\n')
    w.writerow(COLUMNS)
    for r in recs:
        w.writerow([
            r['Slide'], r['Stain'], r['Block'],
            to_int(r['Section']), to_int(r['Slice']),
            clean_text(r['Certainty']), clean_text(r['Tags'])])
