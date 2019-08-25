
# Prereqs

```
sudo apt update
sudo apt install -y unzip make
wget --quiet -O packer.zip https://releases.hashicorp.com/packer/1.4.3/packer_1.4.3_linux_amd64.zip  &&
    unzip packer.zip &&
    rm packer.zip &&
    sudo ln -s $PWD/packer /usr/local/bin/packer
```

(Ansible >= 2.8.5 is required)
```
sudo apt install -y python
virtualenv --python /usr/bin/python ~/.python/ansible 
. ~/.python/ansible/bin/activate
pip install ansible

# installed, we have some problems probably with python3, but this didn't help:
sudo apt install --no-install-recommends --assume-yes python-apt

# install for vnc viewer with shared option, can be used via e.g.: vncviewer -Shared localhost:<port>
sudo apt install -y tigervnc-viewer
```

```
sudo apt install -y qemu-system
```

## Install kvm
https://fabianlee.org/2018/10/06/kvm-creating-an-ubuntu-vm-with-console-only-access/

## checkout repo

```
mkdir ~/code
cd ~/code
git clone https://github.com/c445/image-builder.git
cd image-builder
git checkout caas
```

## build image
```
cd images/capi
make build-qemu-ubuntu-2004
```

## how to debug

Start `packer` with the `-on-error=ask -debug` flag to have the posibility to connect to the instance to troubleshoot the current state (edit `Makefile`).
After that you will get the temporary ssh-key `/tmp/ansible-key<RANDOM_ID>` together with two files called `/tmp/packer-<UUID>-port`/`/tmp/packer-<UUID>-ip` from
 where you get the informations how to connect to the running virtual machine with e.g.:
```bash
ssh -i /tmp/ansible-key772365317 -v builder@127.0.0.1 -p 43123 "/bin/bash -i"
```

## Rerun Ansible if it fails (adjust ips):

(Probably doesn't work exactly like this anymore)
````bash
ansible-playbook --extra-vars "packer_build_name=ubuntu-1804 packer_builder_type=vmware-iso -o IdentitiesOnly=yes"  /home/fedora/code/gopath/src/sigs.k8s.io/capi-dev/image-builder/images/capi/ansible/playbook.yml  --extra-vars "packer_http_addr=172.16.38.1:8290" --extra-vars "kubernetes_rpm_repo=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64 kubernetes_rpm_gpg_key='https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg' kubernetes_rpm_gpg_check=True kubernetes_deb_repo='https://apt.kubernetes.io/ kubernetes-xenial' kubernetes_deb_gpg_key=https://packages.cloud.google.com/apt/doc/apt-key.gpg kubernetes_cni_version=0.7.5-00 kubernetes_cni_semver=v0.7.5 kubernetes_cni_source=pkg kubernetes_semver=v1.15.0 kubernetes_source=pkg kubernetes_version=1.15.0-00"  -i "172.16.38.129," -e "ansible_user=ubuntu ansible_ssh_pass=ubuntu" -c paramiko
````

Or with 
````
ansible_ssh_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa.capi
````

# Upload image

```bash
dhc_openstack os1pi014
openstack image create --disk-format vmdk \
  --private \
  --container-format bare \
  --property vmware_adaptertype="lsiLogicsas" \
  --property vmware_disktype="streamOptimized" \
  --property vmware_ostype="ubuntu64Guest" \
  --file ./output/ubuntu-1804-kube-v1.17.3/qemu-kube-v1.17.3.vmdk ubuntu-1804-kube-v1.17.3

dhc_openstack c99p005
openstack image create --disk-format qcow2 \
  --private \
  --container-format bare \
  --file ./output/ubuntu-1804-kube-v1.17.3/qemu-kube-v1.17.3.qcow2 ubuntu-1804-kube-v1.17.3

```
