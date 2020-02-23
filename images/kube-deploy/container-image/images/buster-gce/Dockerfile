FROM buster-base

# Grow disk to fill available space
RUN apt-get install --yes cloud-initramfs-growroot


# Add google cloud engine debian package repository
RUN apt-get install --yes gnupg
ADD google-cloud.list /etc/apt/sources.list.d/
# gpg key sourced from https://packages.cloud.google.com/apt/doc/apt-key.gpg
ADD apt-key.gpg /
RUN cat /apt-key.gpg | sudo apt-key add -
RUN rm /apt-key.gpg


# Install critical packages
RUN apt-get update
RUN apt-get install --yes google-cloud-packages-archive-keyring
RUN apt-get install --yes google-compute-engine
# Expand root disk to fill available space
RUN apt-get install --yes gce-disk-expand
