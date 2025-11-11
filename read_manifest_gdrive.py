import gspread
import pandas as pd
import argparse
import sys

# Create a parser
parse = argparse.ArgumentParser(
    description="Download HistologyMatching sheet from GDrive")

# Add the arguments
parse.add_argument('--json', '-j', metavar='json', type=str,
                   help="Credentials JSON file for service account")

parse.add_argument('id', metavar='specimen_id', type=str,
                   help='ID of the specimen you want to extract from the sheet')

parse.add_argument('csv', metavar='csv', type=str,
                   help='Output CSV file')

# Parse the arguments
args = parse.parse_args()

# Connect to Google Sheets
gc = gspread.service_account(filename=args.json)

# Load the spreadsheet
sh = gc.open("HistologyMatching")

# Find the worksheet that matches our ID
match = [ x for x in sh.worksheets() if x.title.split('_')[0] == args.id ]
if len(match) != 1:
    match = [ x for x in sh.worksheets() if x.title.startswith(args.id) ]
    if len(match) != 1:
        print("No matches or multiple matches for ID {}: {}".format(args.id, match))
        sys.exit(255)

# Extract the worksheet to PANDAS
recs = match[0].get_all_records()
if len(recs) > 0:
    df = pd.DataFrame(recs)

    # Process a numeric column
    def col_to_int(col):
        col_num = pd.to_numeric(col, errors='coerce')

    # Create a new frame with the required fields converted to numeric format
    df_num = pd.DataFrame({
        'Slide': df.Slide.astype('str'),
        'Stain': df.Stain,
        'Block': df.Block,
        'Section': pd.to_numeric(df.Section, 'coerce', downcast='signed').astype('Int64'),
        'Slice': pd.to_numeric(df.Slice, 'coerce', downcast='signed').astype('Int64'),
        'Certainty': df.Certainty,
        'Tags': df.Tags
    })

    # Write to CSV
    df_num.to_csv(args.csv, index=False)

else:
    df_blank = pd.DataFrame(
        {'Slide': [], 'Stain': [], 'Block': [], 'Section': [], 'Slice': [], 'Certainty': [], 'Tags': []})
    df_blank.to_csv(args.csv, index=False)
