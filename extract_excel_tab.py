#!/usr/bin/env python3
import pandas as pd
import sys

# Process a numeric column
def col_to_int(col):
    col_num = pd.to_numeric(col, errors='coerce')


# Load all sheets as a dict
df_dict = pd.read_excel(sys.argv[1], sheet_name=None)
key_match = [ k for k in df_dict.keys() if k.startswith(sys.argv[2]) ]
if len(key_match) != 1:
    raise ValueError("Worksheet {} not found".format(sys.argv[2]))

df = df_dict[key_match[0]]

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
df_num.to_csv(sys.argv[3], index=False)

