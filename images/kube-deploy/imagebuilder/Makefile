all: gocode

gocode:
	GO111MODULE=on go install sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder

gofmt:
	gofmt -w -s main.go
	gofmt -w -s pkg
