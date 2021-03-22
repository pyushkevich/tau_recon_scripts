#!/usr/bin/env Rscript
library("optparse")
library(ggplot2)
library(dplyr)
library(MASS)

# Read the arguments
option_list <- list(
   make_option(c("-M", "--mri"), type="character", default=NULL,
               help="CSV file containing MRI mask slice statistics",
               metavar="filename"),
   make_option(c("-B", "--blockface"), type="character", default=NULL,
               help="CSV file containing blockface mask slice statistics",
               metavar="filename"),
   make_option(c("-o", "--output"), type="character", default=NULL,
               help="Printf-like pattern for output matrices, %s for block_id",
               metavar="pattern"),
   make_option(c("-P", "--plot"), type="character", default=NULL,
               help="Printf-like pattern for output PDFs with plots, %d for plot index",
               metavar="pattern"),
   make_option(c("-f", "--flip"), action = "store_true", default = FALSE,
               help="Should the z-order be flipped?")
);
opt_parser <- OptionParser(option_list=option_list);
opt <- parse_args(opt_parser);

if (is.null(opt$mri) || is.null(opt$blockface) || is.null(opt$output)){
   print_help(opt_parser)
   stop("Required inputs missing")
}

# Read the blockface data
B<-read.csv(opt$blockface,header=F,col.names = c('id','block','slice','x','y','z','area','perim'))

# Adjust area by spacing (should be done when generating file)
M<-read.csv(opt$mri,header=F,col.names = c('id','x','y','z','area','perim'))

# Adjust area by spacing (should be done when generating file)
B$area = B$area * 0.33 * 0.33
M$area = M$area * 0.2 * 0.2

# Set the flip to either -1 or 1
flip <- ifelse(opt$flip, -1, 1)

# Number of blocks
N=length(levels(as.factor(B$block)))

# This function remaps block z coordinates to MRI
remap_bf_z <- function(B, flip, offset, scale, padding)
{
  padding=c(padding, 0)
  zcurr = offset
  i = 1
  Bz<-B
  Bz$zorig=Bz$z
  for(b in levels(as.factor(B$block))) {
    bz = Bz$z[Bz$block == b]
    if(grepl('a$',b)) {
      bz = bz * flip * scale + zcurr;
    }
    else {
      bz = (bz -min(bz)) * flip * scale + zcurr;
    }
    z1 = ifelse(flip > 0, max(bz), min(bz))
    Bz$z[Bz$block == b] = bz
    zcurr = z1 + flip * padding[i]
    i=i+1
  }

  return(Bz)
}

# Compute initial offset
Br_init = remap_bf_z(B, flip, 0, 1, rep(0.5,N-1));

# Compute the z center of mass for blockface and MRI
zctr_M = sum(M$z * M$area) / sum(M$area);
zctr_Br_init = sum(Br_init$z * Br_init$area) / sum(Br_init$area);

# Set the initial offset
zoff_init = zctr_M - zctr_Br_init

# Check the initialization
Br = remap_bf_z(B, flip, zoff_init, 1, c(0.5,0.5,0.5));
Br$tarea = approx(x=M$z, y=M$area, xout=Br$z, method="linear", yleft=0, yright=0)$y

# Objective function for optimization
objfun<-function(p)
{
  Br = remap_bf_z(B, flip, p[1], 1.0, p[3:length(p)]);
  Br$tarea = approx(x=M$z, y=M$area, xout=Br$z, method="linear", yleft=0, yright=0)$y
  rcoeff=cor(Br$tarea, Br$area, method="spearman")
  print(rcoeff)
  return(1.0 - rcoeff)
}

# Function to plot results
objplt<-function(p, mode)
{
  Br = remap_bf_z(B, flip, p[1], 1., p[3:length(p)]);
  Br$tarea = approx(x=M$z, y=M$area, xout=Br$z, method="linear", yleft=0, yright=0)$y
  sum=summary(rlm(tarea ~ area, data=Br))
  if(mode == 1)
    ggplot(data=Br, aes(x=z,y=area,color=block)) + geom_point() + geom_point(aes(y=tarea, col=NA))
  else
    ggplot(data=Br, aes(x=area, y=tarea, color=block)) + geom_point() +
      ggtitle(paste("Robust regression coefficient: ", round(cor(Br$tarea, Br$area,
                                                                 method="spearman"),6)))
}

# Set up the matrix of constraints (positive paddings)
ui = rbind(c(0,0,1,0,0),
           c(0,0,0,1,0),
           c(0,0,0,0,1))

ci = c(0,0,0)

# Perform actual optimization
res=constrOptim(theta=c(-40, 1.0, rep(0.5, N-1)), f=objfun, method="Nelder-Mead",
                ui=ui, ci=ci, control=list(maxit=5000))

# Compute the optimal mapping
Br = remap_bf_z(B, flip, res$par[1], 1., res$par[3:length(res$par)]);
Br$tarea = approx(x=M$z, y=M$area, xout=Br$z, method="linear", yleft=0, yright=0)$y
Br$tx = approx(x=M$z, y=M$x, xout=Br$z, method="linear", yleft=0, yright=0)$y
Br$ty = approx(x=M$z, y=M$y, xout=Br$z, method="linear", yleft=0, yright=0)$y

# Save output matrices
for(b in levels(as.factor(B$block))) {
  Bi=subset(Br, block=='HR2a')

  # Centroid offsets
  dx = sum(Bi$x * Bi$area)/sum(Bi$area) - sum(Bi$tx * Bi$tarea)/sum(Bi$tarea)
  dy = sum(Bi$y * Bi$area)/sum(Bi$area) - sum(Bi$ty * Bi$tarea)/sum(Bi$tarea)

  model = lm(zorig ~ z, subset(Br, block==b))
  mtx = rbind(c(1, 0, 0, dx),
              c(0, 1, 0, dy),
              c(0, 0, model$coefficients[2], model$coefficients[1]),
              c(0, 0, 0, 1))

  write.table(mtx,
              file=sprintf(opt$output, b),
              row.names=FALSE, col.names=FALSE)
}

# Generate a plot of the result
objplt(res$par, 1)
ggsave(sprintf(opt$plot, 1))

objplt(res$par, 2)
ggsave(sprintf(opt$plot, 2))

