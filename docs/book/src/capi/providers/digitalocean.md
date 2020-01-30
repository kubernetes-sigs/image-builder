# Building Images for DigitalOcean

This directory contains tooling for building base images for use as nodes in Kubernetes Clusters. [Packer](https://www.packer.io) is used for building these images. This tooling has been forked and extended from the [Wardroom](https://github.com/heptiolabs/wardroom) project.

## Prerequisites

### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

### Prerequisites for DigitalOcean

- A DigitalOcean account
- The DigitalOcean CLI ([doctl](https://github.com/digitalocean/doctl#installing-doctl)) installed and configured
- Set environment variables for `DIGITALOCEAN_ACCESS_TOKEN`,

## Building Images

### Building DigitalOcean Image Snapshots

From the images/capi directory, run `make build-do-default`