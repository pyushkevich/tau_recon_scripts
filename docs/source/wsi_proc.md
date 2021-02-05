# Whole-slide histology slide processing

## Converting to OpenSlide compatible format

[OpenSlide](https://openslide.org/api/python/) is a library with a Python interface for reading whole-slide images. Not all slide scanners generate OpenSlide-copmatible files. These notes descibe how to convert images to this format.

* You need to install the package [VIPS](https://github.com/libvips/libvips) as described [here](https://libvips.github.io/libvips/install.html)

* For most files, this command works:

      vips tiffsave input_file.ext output_file.tiff \
           --vips-progress --compression=jpeg --Q=80 \
           --tile --tile-width=256 --tile-height=256 \
           --pyramid --bigtiff
           
  