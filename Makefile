GO15VENDOREXPERIMENT=1
APP=kube-gce-dns

ifeq ($(CIRCLE_BUILD_NUM),)
	BUILD_NUM := dev
else
	BUILD_NUM := $(CIRCLE_BUILD_NUM)
endif

all: _deps test build

build: ## run go build, build the binaries
	go build

build-docker: _fetch-cert _build-linux ## build the docker container
	docker build -t quay.io/getpantheon/$(APP):$(BUILD_NUM)  .

coveralls: _coverage ## run coverage report
	goveralls -repotoken $$COVERALLS_TOKEN -service=circleci -coverprofile=coverage.out

deploy: ## deploy to kube
	kubectl rolling-update $(APP) --poll-interval="500ms" --image  --image=quay.io/getpantheon/$(APP):$(BUILD_NUM)

force-pod-restart: ## force kube pods
	kubectl get  pod -l"app=$(APP)" --no-headers | awk '{print $$1}' | xargs kubectl delete pod

push: build-docker ## push container
	docker push quay.io/getpantheon/$(APP):$(BUILD_NUM)

test: ## run the go tests
	go test

update-deps: _gvt-install ## Update all the Go deps recursively. If you do this then manually change docker-parsers to 0f5c9d301b9b1cca66b3ea0f9dec3b5317d3686d see: https://github.com/kubernetes/kubernetes/issues/18774
	go get github.com/cespare/deplist
	rm  -rf vendor/
	for i in $(shell go list -f '{{.ImportPath}}' ./... | xargs -n 1 deplist | grep -v $(APP) | sort -u); do gvt fetch  $$i ;  done

update-secrets: ## update secrets
	kubectl replace -f deploy/gce/k8s/ssl.yml
	kubectl replace -f deploy/gce/k8s/secrets.yml

_build-linux:
	GOOS=linux go build

_coverage:
	go get github.com/pierrre/gotestcover
	go get github.com/mattn/goveralls
	gotestcover -coverprofile=coverage.out $$(go list ./... | grep -v /vendor/)

_deps: _gvt-install
	gvt rebuild

_deps-circle:
	bash deploy/gce/gcloud-setup.sh
	bash deploy/install-go.sh
_fetch-cert:
	curl https://raw.githubusercontent.com/bagder/ca-bundle/master/ca-bundle.crt -o ca-certificates.crt

_gvt-install:
	go get -u github.com/FiloSottile/gvt

help: ## print list of tasks and descriptions
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

.PHONY: all help deploy
