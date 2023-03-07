# konfigadm image-builder

## Prerequisites

* Nested Virtualization (or lots of patience)
* Qemu
* konfigadm >= 0.4.0
* Linux or macOS

## Building new images

```bash
konfigadm images build --image ubuntu180 --resize +2G k8s-1.15.yml
```

## Customizing images

Create one or more konfigadm specs e.g. `custom.yml`

```bash
konfigadm images build --image ubuntu180 --resize +2G k8s-1.15.yml custom.yml
```

## Uploading images to a cloud

```bash
konfigadm images upload ova --image ubuntu1804.img
```

## Testing images

```
make setup
make ubuntu1804
```
