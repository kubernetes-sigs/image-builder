FROM golang:1.11 AS build

WORKDIR /go/src/k8s.io/kube-deploy/imagebuilder
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build

FROM alpine:3.8
WORKDIR /imagebuilder
RUN apk add --no-cache ca-certificates
COPY --from=build /go/src/k8s.io/kube-deploy/imagebuilder/imagebuilder imagebuilder
ADD templates/ /imagebuilder/config/templates/
ADD aws*.yaml gce*.yaml /imagebuilder/config/
ENTRYPOINT ["/imagebuilder/imagebuilder"]
