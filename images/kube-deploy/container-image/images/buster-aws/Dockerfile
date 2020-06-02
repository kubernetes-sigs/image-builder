FROM buster-base

# cloud-init is responsible for e.g. running the ec2 user-data script,
# along with general network configuration and disk resizing.
# We pre-select Ec2 mode, mostly as an optimization - everything seems to work regardless.
RUN echo "cloud-init    cloud-init/datasources    multiselect    Ec2" | debconf-set-selections
RUN apt-get -y install --no-install-recommends cloud-init

# Configure default user (admin) to match debian default image
# https://salsa.debian.org/cloud-team/debian-cloud-images/-/blob/master/config_space/files/etc/cloud/cloud.cfg.d/01_debian_cloud.cfg/EC2
COPY 01_debian_cloud.cfg /etc/cloud/cloud.cfg.d/

RUN echo "cloud-init    cloud-init/datasources    multiselect    Ec2" | debconf-set-selections
RUN apt-get -y install --no-install-recommends cloud-init
