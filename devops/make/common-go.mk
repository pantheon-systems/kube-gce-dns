# Common  Go Tasks
#
# INPUT VARIABLES
# - COVERALLS_TOKEN: Token to use when pushing coverage to coveralls.
#
# - FETCH_CA_CERT: The presence of this variable will cause the root CA certs
#                  to be downloaded to the file ca-certificates.crt before building.
#                  This can then be copied into the docker container.
#
#-------------------------------------------------------------------------------

## Append tasks to the global tasks
deps:: deps-go
deps-circle:: deps-circle-go deps
lint:: lint-go
test:: test-go
test-circle:: test test-coveralls
test-coverage:: test-coverage-go
build:: build-go

## dependency manager detection
ifeq (,$(wildcard vendor/manifest))
  USE_DEP = 1
else
  USE_GVT = 1
endif

## go tasks

build-go:: ## build project for current arch
	$(call INFO, "building project for current architecture")
	@go build > /dev/null

build-linux:: _fetch-cert ## build project for linux
	$(call INFO, "building project for linux")
	@GOOS=linux CGO_ENABLED=0 go build -ldflags="-s -w" > /dev/null

build-circle:: build-linux ## build project for linux. If you need docker you will have to invoke that with an extension

deps-go:: _go-install-dep-tools deps-lint ## install dependencies for project assumes you have go binary installed
ifneq (,$(wildcard vendor))
	@find  ./vendor/* -maxdepth 0 -type d -exec rm -rf "{}" \;
endif
ifdef USE_GVT
	$(call INFO, "restoring dependencies with \'gvt\'")
	@gvt rebuild > /dev/null
endif
ifdef USE_DEP
	$(call INFO, "ensuring dependencies with \'dep\'")
ifdef CIRCLECI
	@cd $$(readlink -f "$$(pwd)") && dep ensure > /dev/null
else
	@dep ensure > /dev/null
endif
endif

# for now we disable gotype because its vendor suport is mostly broken
#  https://github.com/alecthomas/gometalinter/issues/91
lint-go:: deps-lint
	$(call INFO, "scanning source with gometalinter")
	@gometalinter.v1 --vendor --enable-gc -Dstaticcheck -Dgotype -Ddupl -Dgocyclo -Dinterfacer -Daligncheck -Dunconvert -Dvarcheck  -Dstructcheck -E vet -E golint -E gofmt -E unused --deadline=80s
	@gometalinter.v1 --vendor --enable-gc --disable-all -E staticcheck --deadline=60s
	@gometalinter.v1 --vendor --enable-gc --disable-all -E interfacer -E aligncheck --deadline=30s
	@gometalinter.v1 --vendor --enable-gc --disable-all -E unconvert -E varcheck   --deadline=30s
	@gometalinter.v1 --vendor --enable-gc --disable-all -E structcheck  --deadline=30s

test-go:: lint  ## run go tests (fmt vet)
	$(call INFO, "running tests with race detection")
	@go test -race -v $$(go list ./... | grep -v /vendor/)

# also add go tests to the global test target
test:: test-go

test-no-race:: lint ## run tests without race detector
	$(call INFO, "running tests without race detection")
	@go test -v $$(go list ./... | grep -v /vendor/)


deps-circle-go:: ## install Go build and test dependencies on Circle-CI
	$(call INFO, "installing the go binary @$(GOVERSION)")
	@bash devops/make/sh/install-go.sh

deps-lint::
ifeq (, $(shell which gometalinter.v1))
	$(call INFO, "installing gometalinter")
	@go get -u gopkg.in/alecthomas/gometalinter.v1 > /dev/null
	@gometalinter.v1 --install > /dev/null
else
	$(call INFO, "gometalinter already installed")
endif

deps-coverage::
ifeq (, $(shell which gotestcover))
	$(call INFO, "installing gotestcover")
	@go get github.com/pierrre/gotestcover > /dev/null
endif
ifeq (, $(shell which goveralls))
	$(call INFO, "installing goveralls")
	@go get github.com/mattn/goveralls > /dev/null
endif

deps-status:: ## check status of deps with gostatus
ifeq (, $(shell which gostatus))
	$(call INFO, "installing gostatus")
	@go get -u github.com/shurcooL/gostatus > /dev/null
endif
	@go list -f '{{join .Deps "\n"}}' . | gostatus -stdin -v

test-coverage-go:: deps-coverage ## run coverage report
	$(call INFO, "running gotestcover")
	@gotestcover -v -coverprofile=coverage.out $$(go list ./... | grep -v /vendor/) > /dev/null

test-coveralls:: test-coverage-go ## run coverage and report to coveralls
ifdef COVERALLS_TOKEN
	$(call INFO, "reporting coverage to coveralls")
	@goveralls -repotoken $$COVERALLS_TOKEN -service=circleci -coverprofile=coverage.out > /dev/null
else
	$(call ERROR, "You asked to use Coveralls, but neglected to set the COVERALLS_TOKEN environment variable")
endif

test-coverage-html:: test-coverage ## output html coverage file
	$(call INFO, "generating html coverage report")
	@go tool cover -html=coverage.out > /dev/null

# this will detect if the project is dep or not and use it if it is. If not install gvt
# if no manifest then its probably dep
_go-install-dep-tools:
ifdef USE_GVT
	@make _go-install-gvt
endif
ifdef USE_DEP
	@make _go-install-dep
endif

_go-install-gvt::
ifeq (, $(shell which gvt))
	$(call INFO, "installing 'gvt' go dependency tool")
	@go get -u github.com/FiloSottile/gvt > /dev/null
endif

_go-install-dep::
ifeq (, $(shell which dep))
	$(call INFO, "installing 'dep' go dependency tool")
	@go get -u github.com/golang/dep/... > /dev/null
endif


_fetch-cert::
ifdef FETCH_CA_CERT
	$(call INFO, "fetching CA certs from haxx.se")
	@curl -s -L https://curl.haxx.se/ca/cacert.pem -o ca-certificates.crt > /dev/null
endif

.PHONY:: _fetch-cert _gvt-install test-coverage-html test-coveralls deps-status deps-coverage deps-circle deps-go test-circle test-go build-circle build-linux build-go
