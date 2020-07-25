# Building Images for DigitalOcean

## Prerequisites for DigitalOcean

- A DigitalOcean account
- The DigitalOcean CLI ([doctl](https://github.com/digitalocean/doctl#installing-doctl)) installed and configured
- Set environment variables for `DIGITALOCEAN_ACCESS_TOKEN`,

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Digital Ocean images are managed by running:

```bash
make deps-do
```

### Building DigitalOcean Image Snapshots

From the `images/capi` directory, run `make build-do-default`
