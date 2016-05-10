REGISTRY := quay.io/getpantheon
APP := kube-gce-dns
GO15VENDOREXPERIMENT=1

# determinse the docker tag to build
ifeq ($(CIRCLE_BUILD_NUM),)
	BUILD_NUM := dev
else
	BUILD_NUM := $(CIRCLE_BUILD_NUM)
endif
IMAGE := $(REGISTRY)/$(APP):$(BUILD_NUM)

# deps
gvt_install:  ## install the gvt util
	go get -u github.com/FiloSottile/gvt

deps: gvt_install
	gvt rebuild || true

cover_deps:
	go get github.com/pierrre/gotestcover
	go get github.com/mattn/goveralls

# tests
test: ## run all tests
ifeq ($(CIRCLECI), true)
	go version
	go env
endif
	go test -v $$(go list ./... | grep -v /vendor/)
	go build -v -race

cov: cover_deps ## generate coverage report (coverage.out)
	gotestcover -coverprofile=coverage.out $$(go list ./... | grep -v /vendor/)

coveralls: cov ## update coveralls (requires $COVERALLS_TOKEN set)
	goveralls -repotoken $$COVERALLS_TOKEN -service=circleci -coverprofile=coverage.out

cov_html: cov ## generate coverage report in html and open a browser
	go tool cover -html=coverage.out

# build / compile
clean: ## remove test and build artifacts
	rm -f $(APP) coverage.out

build_osx: *.go ## build for osx
	GOOS=darwin CGO_ENABLED=0 go build -a .

build_linux: *.go ## build for linux
	GOOS=linux CGO_ENABLED=0  go build -a .

cert:
	curl https://curl.haxx.se/ca/cacert.pem -o ca-certificates.crt

build_docker: cert build_linux ## build docker container
	docker build -t $(IMAGE) .

fix_circle_go: # ensure go 1.6 is setup
	scripts/circle-go.sh

deploy: push ## push the image to quay

push: build_docker ## push container to docker registry
	docker push $(IMAGE)

help: ## print list of tasks and descriptions
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

.PHONY: deps gvt_install clean test
