# Hack

This directory has a collection of scripts that dont belong elsewhere and may go away some day.

## serve-artifacts.go

This script finds all relevant k8s artifacts (i.e. like the kubelet.exe) in a directory , serves them on an endpoint.

It prints out the values corresponding to this endpoint so you can use it in input to image builder, i.e.


```
jayunit100@kcp-1:~/SOURCE/image-builder/images/capi/hack$ go run serve_artifacts.go 
kubernetes_base_url: http://127.0.0.1:8080/my/k8s
cloudbase_init_url: http://127.0.0.1:8080/**none**
wins_url: http://127.0.0.1:8080/**none**
nssm_url: http://127.0.0.1:8080/**none**
``` 

It has no dependencies, and this is intentional - it is just an example script for surfacing artifacts to image builder,
to be adopted by vendors as needed
