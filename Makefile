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
	gvt rebuild

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

build_docker: build_linux ## build docker container
	docker build -t $(IMAGE) .

# package/deploy
circle_kube_deps:
	scripts/k8s/gcloud_setup.sh

fix_circle_go: # ensure go 1.6 is setup
	scripts/install-go.sh

deploy: push update_rc ## push the image, update the rc in kube

push: build_docker ## push container to docker registry
	docker push $(IMAGE)

update_rc: ## update the kubernetes replication controller
	kubectl --namespace=kube-system delete rc kube-gce-dns || true
	sed -e "s#__IMAGE__#$(IMAGE)#g" ;\
	sed -e "s#__PROJECT__#$(GCLOUDSDK_CORE_PROJECT)#g" ;\
	sed -e "s#__DOMAIN__#$(DOMAIN)#g" \
			scripts/k8s/rc.yaml.template \
			| kubectl apply --namespace=kube-system -f -

help: ## print list of tasks and descriptions
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

.PHONY: deps gvt_install clean test
