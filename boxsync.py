from box_sdk_gen import BoxClient, BoxDeveloperTokenAuth
import os
import datetime
import hashlib
from io import BytesIO
import re
import argparse
import pandas as pd

# --- Authentication ---
def connect_box(token):
    auth = BoxDeveloperTokenAuth(token=token)
    client = BoxClient(auth=auth)
    return client

# Check if the box file is newer than local
def is_different(box_file, local_folder, local_filename=None):
    """Return True if Box file newer than from local."""
    if local_filename is None:
        local_filename = box_file.name
    fn_out = os.path.join(local_folder, local_filename)
    if not os.path.exists(fn_out):
        return True
    sha1 = hashlib.sha1()
    with open(fn_out, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            sha1.update(chunk)
    return sha1.hexdigest() != box_file.sha_1

# Download file locally
def download_to_folder(client, box_file, local_folder, local_filename=None, exist_ok=False):
    # Create destination folder
    os.makedirs(local_folder, exist_ok=True)

    # Check if file exists; return false if not downloading
    if local_filename is None:
        local_filename = box_file.name
    fn_out = os.path.join(local_folder, local_filename)
    if os.path.exists(fn_out) and exist_ok is False:
        return False

    # Download the file
    sha1 = hashlib.sha1()
    bs = client.downloads.download_file(box_file.id)
    with open(fn_out, 'wb') as fout:
        while True:
            chunk = bs.read()
            if chunk is None or len(chunk)==0:
                break
            sha1.update(chunk)
            fout.write(chunk)
        fout.close()
        if sha1.hexdigest() != box_file.sha_1:
            raise Exception(f'SHA-1 mismatch between box file {box_file.id} and destination {fn_out}')
    return True

# Check if any of the required files are missing in box folder
def check_file_list(client, folder, needed_files):
    files = client.folders.get_folder_items(folder.id)
    fd_found = []
    fn_missing = []
    for x in files.entries:
        if x.name in needed_files:
            fd_found.append(x)
        else:
            fn_missing.append(x.name)
    return fd_found, fn_missing

# Fix issues with filenames
ex_hnl = re.compile(r'HNL[-_]([0-9]{2})[-_]([0-9]{2})([LR]|).*')
ex_indd = re.compile(r'INDD([0-9]{6})(\.[0-9]{2}|)([LR]|).*')
def fixid_molds(id):
    if ex_hnl.match(id):
        return ex_hnl.sub(r'HNL-\1-\2', id)
    elif ex_indd.match(id):
        return ex_indd.sub(r'INDD\1\2', id).replace('.','x')
    else:
        return None
    
# Sync mold files from Box
def sync_mold_files(token, box_folder_id, local_dir, id):
    
    # Connect to Box
    client = connect_box(token)
    items = client.folders.get_folder_items(box_folder_id)
    
    # Locate folder that contains mold for this ID
    matches = []
    for item in items.entries:
        true_id = fixid_molds(item.name)
        if item.type == 'folder' and true_id == id:
           matches.append(item)
           
    # Check matches
    if len(matches) != 1:
        raise Exception(f'Could not find unique folder for ID {id} in Box folder {box_folder_id}; found {len(matches)} matches.')
    
    # This is the mold folder
    mold_folder = matches[0] 
    
    # Download the files
    needed_files = 'mtl7t.nii.gz contour_image.nii.gz slitmold.nii.gz holderrotation.mat'.split()
    fd_found, fn_missing = check_file_list(client, mold_folder, needed_files)
    if len(fn_missing) > 0:
        print(f'Missing files for mold ID {id} in Box folder {box_folder_id}: {fn_missing}')
        
    # Download files that are not missing
    for f in fd_found:
        if is_different(f, local_dir):
            print(f'Downloading mold file {f.name} for ID {id}...')
            download_to_folder(client, f, local_dir, exist_ok=True)
        else:
            print(f'Mold file {f.name} for ID {id} is up to date; skipping download.')
            

# Regex for the folders
exbf_hnl = re.compile(r'HNL([0-9]{2})[-_]([0-9]{2})([LR]|).*')
exbf_indd = re.compile(r'UP([0-9]{2,3})_([0-9]{2})([LR]|) (.*)')

# Regex for the filenames
exbf_fn = re.compile(r'(UP[0-9]{2,3}_[0-9]{2}|HNL[0-9]{2}_[0-9]{2})[LR]_(H[LR][1-5][ap])__([0-9]{2})_([0-9]{2}).jpg')

def fixid_bf(id):
    if exbf_hnl.match(id):
        return None, exbf_hnl.sub(r'HNL-\1-\2', id)
    elif exbf_indd.match(id):
        up_part = exbf_indd.sub(r'UP\1-\2', id)
        indd_part = exbf_indd.sub(r'\4', id).replace('.','x')
        indd_part = indd_part.strip(' ()LR').replace(' ','').replace('.','x')
        return up_part, indd_part
    else:
        return None, None

def fix_bf_fname(fn, id):
    fn = fn.replace(' ','')
    if exbf_fn.match(fn):
        block,section,slide = exbf_fn.sub(r'\2,\3,\4', fn).split(',')
        fname = f'{id}_{block}_{section}_{slide}.jpg'
        return fname,block,section,slide
    else:
        return None
            
# Sync blockface images from Box
def sync_blockface_images(token, box_folder_id, local_dir, id):
    
    # Connect to Box
    client = connect_box(token)
    items = client.folders.get_folder_items(box_folder_id)
    
    # Find a match
    items = client.folders.get_folder_items(box_folder_id)
    matches = []
    for item in items.entries:
        up_name, fix_name = fixid_bf(item.name)
        if fix_name == id:
            matches.append(item)

    # Check matches
    if len(matches) != 1:
        raise Exception(f'Could not find unique folder for ID {id} in Box folder {box_folder_id}; found {len(matches)} matches.')
    
    # List folders in there
    items = client.folders.get_folder_items(matches[0].id)
    matched_slides = []
    file_refs = []
    for item in items.entries:
        files = client.folders.get_folder_items(item.id, limit=1000)
        for fn in files.entries:
            fix = fix_bf_fname(fn.name, id)
            if fix is None:
                raise Exception(f'Failed to parse filename {fn.name}')
            else:
                matched_slides.append({
                    'Slide': fix[0], 
                    'Stain': 'Blockface',
                    'Block': fix[1],
                    'Section': fix[2],
                    'Slice': fix[3],
                    'Certainty': ''})
                file_refs.append(fn)

    df = pd.DataFrame(matched_slides)
    
    # Download the individual files into the folder
    bf_raw_dir = os.path.join(local_dir, 'bf_raw')

    for f, row in zip(file_refs, df.itertuples()):
        if is_different(f, bf_raw_dir, local_filename=row.Slide):
            print(f'Downloading blockface image {f.name} for ID {id}...')
            download_to_folder(client, f, bf_raw_dir, exist_ok=True, local_filename=row.Slide)
        else:
            print(f'Blockface image {f.name} for ID {id} is up to date; skipping download.')            
            
    # Save the CSV file
    manifest_dir = os.path.join(local_dir, 'manifest')
    os.makedirs(manifest_dir, exist_ok=True)
    bf_manifest_csv = os.path.join(manifest_dir, f'bf_manifest_{id}.txt')
    df.to_csv(bf_manifest_csv, index=False)
    print(f'Saved blockface manifest CSV to {bf_manifest_csv}')


# Create main parser
parser = argparse.ArgumentParser(description='Sync remote Box files to local folders')
parser.add_argument('--token', type=str, required=False, help='Box developer token')

# If token is not provided, try to read from environment variable
if 'BOX_DEVELOPER_TOKEN' in os.environ:
    parser.set_defaults(token=os.environ['BOX_DEVELOPER_TOKEN'])

# Create subparser for syncing molds
subparsers = parser.add_subparsers(dest='command')
mold_parser = subparsers.add_parser('sync_mold', help='Sync 3D printing mold files from Box')
mold_parser.add_argument('--box_folder_id', '-b', type=str, required=True, 
                         help='Box folder ID containing mold folders')
mold_parser.add_argument('--local_dir', '-l', type=str, required=True, 
                         help='Local directory to save mold files')
mold_parser.add_argument('--id', '-i', type=str, required=True,
                         help='Specific mold ID to sync')

# Create subparser for downloading blockface images
bl_parser = subparsers.add_parser('sync_bf', help='Sync blockface images from Box')
bl_parser.add_argument('--box_folder_id', '-b', type=str, required=True, 
                        help='Box folder ID containing blockface image folders')
bl_parser.add_argument('--local_dir', '-l', type=str, required=True, 
                        help='Local directory to save blockface images')
bl_parser.add_argument('--id', '-i', type=str, required=True,
                        help='Specific specimen ID to sync')

# Call the appropriate function based on command
args = parser.parse_args()

# If no token provided, print useful message how to set it
if not args.token:
    parser.error('Box developer token (https://app.box.com/developers/console) must be provided via --token or BOX_DEVELOPER_TOKEN environment variable.')

if args.command == 'sync_mold':
    sync_mold_files(args.token, args.box_folder_id, args.local_dir, args.id)
elif args.command == 'sync_bf':
    sync_blockface_images(args.token, args.box_folder_id, args.local_dir, args.id)
