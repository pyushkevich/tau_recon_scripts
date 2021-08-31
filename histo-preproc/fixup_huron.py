#!/usr/bin/env python 
import bitstring as bs
import sys
import argparse

# Define arguments
parser = argparse.ArgumentParser()
parser.add_argument('input')
parser.add_argument('output')
args = parser.parse_args()

def write_bytes(src, dest, n, stride=64 * 1048576):
    print('Writing %4.1fGb chunk. Each dot is %4.1fMb' % (n / 1024.**3, stride / 1024.**2))
    for p in range(0, n, stride):
        chunk=min(stride, n-p)
        dest.write(src.read('bytes:%d' % (chunk,)))
        sys.stdout.write('.')
        sys.stdout.flush()
    sys.stdout.write('\n')


# Create bitstream
s = bs.ConstBitStream(filename=args.input)

# Read the endianness and assign tags
code_format = s.read('hex:16')
if code_format == '4949':
    u16,u32,u64 = 'uintle:16', 'uintle:32', 'uintle:64'
elif code_format == '4d4d':
    u16,u32,u64 = 'uintbe:16', 'uintbe:32', 'uintbe:64'
else:
    raise Exception('Not a valid TIFF file')

# Read the format (Tiff or BigTiff)
code_version = s.read(u16)
if code_version == 42:
    addr_size = 4
    uaddr = u32
    utags = u16
    taglen = 12
    s.bytepos = 4
elif code_version == 43:
    addr_size = 8
    uaddr = u64
    utags = u64
    taglen = 20
    s.bytepos = 8
else:
    raise Exception('Not a valid TIFF file')

# Array of description offsets and lenghs
desc = []

# Read the offset to IFD
ifd_offset = s.read(uaddr)
while ifd_offset > 0:
    s.bytepos = ifd_offset
    n_tags = s.read(utags)
    for i in range(n_tags):
        tpos = s.bytepos
        tag = s.read(u16)
        tag_type = s.read(u16)
        nval = s.read(uaddr)
        offset = s.read(uaddr)
        # print('tag: ', tag, tag_type, nval, offset)
        if tag == 270:
            desc.append((tpos, nval, offset))

    ifd_offset = s.read(uaddr)

# The tag we will be changing
tpos, nval, offset = desc[0]
s.bytepos = offset
desc = s.peek('bytes:%d' % (nval,))
# print(desc)

# Open output file for writing
of = open(args.output, 'wb')

# Write everything up to the first desc tag
s.bytepos = 0
write_bytes(s, of, tpos)

# Override the new tag
desc_new = b'Aperio SVS generated from Huron Digital Pathology TIF\n' + desc
t = bs.BitArray()
t.append('%s=%d' % (u16, 270))
t.append('%s=%d' % (u16, 2))
t.append('%s=%d' % (uaddr, len(desc_new)))
t.append('%s=%d' % (uaddr, len(s) / 8))
of.write(t.bytes)

# Skip the length of the tag
s.bytepos += 20
write_bytes(s, of, len(s) // 8 - s.bytepos)

# Write the new description
of.write(desc_new)
of.close()
