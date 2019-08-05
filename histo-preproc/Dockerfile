# Need CUDA!
FROM pyushkevich/itksnap:v3.8.0-beta

# Some packages
RUN apt-get update
RUN apt-get install -y curl gcc openslide-tools python2.7

# Downloading gcloud package
RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz

# Installing the package
RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && bash /usr/local/gcloud/google-cloud-sdk/install.sh --quiet

# Adding the package path to local
ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

# Copy internals
COPY . /app/

# Run pip
RUN pip install -r /app/requirements.txt

