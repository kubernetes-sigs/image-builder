FROM golang:1.13 AS build

WORKDIR /go/src/sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build

FROM alpine:3.11
WORKDIR /imagebuilder
RUN apk add --no-cache ca-certificates
COPY --from=build /go/src/sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder/imagebuilder imagebuilder
ADD templates/ /imagebuilder/config/templates/
ADD aws*.yaml gce*.yaml /imagebuilder/config/
ENTRYPOINT ["/imagebuilder/imagebuilder"]
