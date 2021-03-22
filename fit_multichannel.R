#!/usr/bin/env Rscript
library("optparse")
library('oro.nifti');
library('methods');
library('MASS')

# Read the arguments
option_list <- list(
   make_option(c("-M", "--manifest"), type="character", default=NULL, 
               help="Manifest file name for multi-slice mode. File must have 4 columns for multichannel image, mask, target and output",
               metavar="filename"),
   make_option(c("-i", "--input"), type="character", default=NULL,
               help="Input multichannel image file for single-image mode",
               metavar="filename"),
   make_option(c("-t", "--target"), type="character", default=NULL,
               help="Input target image file for single-image mode",
               metavar="filename"),
   make_option(c("-o", "--output"), type="character", default=NULL,
               help="Output image file for single-image mode",
               metavar="filename"),
   make_option(c("-m", "--mask"), type="character", default=NULL,
               help="Input foreground mask file for single-image mode",
               metavar="filename"),
   make_option(c("--sfg"), type="integer", default=500,
               help="Number of samples per slide from the masked region (default: 500)", metavar="int"),
   make_option(c("--sbg"), type="integer", default=100, 
               help="Number of samples per slide from the background region (default: 100)", metavar="int")
); 

# Parse options
opt_parser <- OptionParser(option_list=option_list);
opt <- parse_args(opt_parser);

# Check single-mode parameters
if (!is.null(opt$manifest)) {
   manifest.mode <- TRUE;
} else if (!is.null(opt$input) && !is.null(opt$target) && !is.null(opt$output)) {
   manifest.mode <- FALSE;
} else {
   print_help(opt_parser);
   stop("Required image inputs are missing.n", call.=FALSE);
}

# Read the manifest file and parse it as a dataframe
if(manifest.mode) {
   M <- read.csv(opt$manifest, header=FALSE, sep=" ",
                col.names = c('features','mask','target','result'),
                colClasses = c('character','character','character','character'));
} else {
   M <- data.frame(features = opt$input,
                   mask = ifelse(is.null(opt$mask), "", opt$mask),
                   target = opt$target,
                   result = opt$output);
}

# Read the input data and append to the main matrix
for (row in seq_len(nrow(M))) {

   print(paste('Sampling:', M$features[row]))
   
   # Read the three images and convert to matrices
   f.nii <- readNIfTI(as.character(M$features[row]));
   nfeat <- dim(f.nii)[length(dim(f.nii))];
   f.mat <- matrix(f.nii[],, nfeat);

   t.nii <- readNIfTI(as.character(M$target[row]));
   t.mat <- matrix(t.nii[],,1);

   # Number of samples taken
   sfg = opt$sfg * dim(f.nii)[3];
   sbg = opt$sbg * dim(f.nii)[3];

   # Apply mask if provided
   if(M$mask[row] != "") {
      m.nii <- readNIfTI(M$mask[row]);
      m.mat <- matrix(m.nii[],,1);
      r.fg <- m.mat > 0;
      r.bg <- m.mat == 0;
   }
   else {
      r.fg <- !is.na(t.mat)
      r.bg <- is.na(t.mat)
   }

   # Training sample - inside the mask
   f.fg <- f.mat[r.fg,];
   f.bg <- f.mat[r.bg,];
   t.fg <- matrix(t.mat[r.fg,],,1);
   t.bg <- matrix(t.mat[r.bg,],,1);
   
   # Get foreground/background samples
   if(sum(r.fg) > 0 && sum(r.bg) > 0) {
      sam.fg <- sample.int(sum(r.fg), sfg);
      sam.bg <- sample.int(sum(r.bg), sbg);
      f.sam <- rbind(f.fg[sam.fg,], f.bg[sam.bg,]);
      t.sam <- rbind(matrix(t.fg[sam.fg,],,1), matrix(t.bg[sam.bg,],,1));
   }
   else if(sum(r.fg) > 0) {
      sam.fg <- sample.int(sum(r.fg), sfg);
      f.sam <- f.fg[sam.fg,];
      t.sam <- matrix(t.fg[sam.fg,],,1);
   }
   else if(sum(r.bg) > 0) {
      sam.bg <- sample.int(sum(r.bg), sbg);
      f.sam <- f.bg[sam.bg,];
      t.sam <- matrix(t.bg[sam.bg,],,1);
   }

   # Append the samples to the large sample array
   if (row == 1) {
      all.f.sam <- f.sam
      all.t.sam <- t.sam
   }
   else {
      all.f.sam <- rbind(all.f.sam, f.sam)
      all.t.sam <- rbind(all.t.sam, t.sam)
   }
}

# We how have read all the data in. We can do regression
print(dim(f.fg))
print(dim(t.fg))
print(dim(f.bg))
print(dim(t.bg))
print(dim(all.f.sam))
print(dim(all.t.sam))
df <- data.frame(y=all.t.sam, x=all.f.sam)

# Uggly!
# Test
model <- rlm(y ~ ., data=df);
print(model)

# Second pass: prediction
for (row in seq_len(nrow(M))) {

   print(paste('Predicting:', M$features[row]))

   # Read the three images again
   if(nrow(M) > 1) {
      f.nii <- readNIfTI(as.character(M$features[row]));
      nfeat <- dim(f.nii)[length(dim(f.nii))];
      f.mat <- matrix(f.nii[],, nfeat);
      t.nii <- readNIfTI(as.character(M$target[row]));
      t.mat <- matrix(t.nii[],,1);
   }

   # Predict all intensities
   t.sim <- predict(model, data.frame(x=f.mat));
   
   # Clip predicted intensities (why?)
   t.min <- min(t.mat);
   t.max <- max(t.mat);
   t.sim[t.sim < t.min] = t.min;
   t.sim[t.sim > t.max] = t.max;

   # Save result
   r.nii <- t.nii;
   r.nii[] <- t.sim[]; # matrix(t.sim,c(dim(t.nii),1))
   print(r.nii)
   writeNIfTI(r.nii,gsub("\\..*","",M$result[row]));
}
