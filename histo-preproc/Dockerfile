# Need CUDA!
FROM nvidia/cuda:11.6.1-devel-ubuntu20.04

# Some packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -y tzdata
RUN apt-get install -y wget gcc openslide-tools python3
RUN apt-get install -y build-essential pkg-config glib2.0-dev
RUN apt-get install -y libexpat1-dev libtiff5-dev libjpeg-dev libgsf-1-dev
RUN apt-get install -y curl

# Downloading gcloud package
RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz

# Installing the package
RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && bash /usr/local/gcloud/google-cloud-sdk/install.sh --quiet

# Install ImageMagick
RUN apt-get update && apt-get install -y imagemagick

# Install VIPS
ARG VIPS_VERSION=8.8.0
ARG VIPS_URL=https://github.com/libvips/libvips/releases/download
RUN wget ${VIPS_URL}/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.gz \
  && tar xf vips-${VIPS_VERSION}.tar.gz \
  && cd vips-${VIPS_VERSION} \
  && ./configure \
  && make V=0 \
  && make install

# Adding the package path to local
ENV PATH=$PATH:/usr/local/gcloud/google-cloud-sdk/bin
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Run pip
RUN apt-get install -y python3-pip
COPY requirements.txt /app/
RUN pip install -r /app/requirements.txt

# Copy internals
WORKDIR /app
COPY . /app/

