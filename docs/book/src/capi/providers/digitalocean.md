# Building Images for DigitalOcean

## Prerequisites

The `make deps-do` target will test that Ansible and Packer are installed and available. If they are not, they will be installed to `images/capi/.bin`. This directory will need to be added to your `$PATH`.

### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

### Prerequisites for DigitalOcean

- A DigitalOcean account
- The DigitalOcean CLI ([doctl](https://github.com/digitalocean/doctl#installing-doctl)) installed and configured
- Set environment variables for `DIGITALOCEAN_ACCESS_TOKEN`,

## Building Images

### Building DigitalOcean Image Snapshots

From the `images/capi` directory, run `make build-do-default`
