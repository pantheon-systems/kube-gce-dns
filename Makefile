include common.mk
include common-docs.mk
include common-go.mk
include common-docker.mk
include common-kube.mk
include common-shell.mk
include common-pants.mk

# Required Input Variables for common-python and a default value
PYTHON_PACKAGE_NAME=dummy
TEST_RUNNER=trial
include common-python.mk

# Required Input Variables for common-conda and a default value
CONDA_PACKAGE_NAME=dummy
CONDA_PACKAGE_VERSION=0.0.1
include common-conda.mk

NAMESPACE=sandbox-common-make-test
APP=common-make

test-common: test-shell test-readme-toc test-common-make test-common-kube test-common-docker test-common-pants test-common-go

test-common-lint:
	$(call INFO, "running common make tests $(NAMESPACE)")
	@! make test-common --warn-undefined-variables --just-print 2>&1 >/dev/null | grep warning

test-common-make: clean-common-make
	$(call INFO, "running kube common tests $(NAMESPACE)")
	@kubectl create namespace $(NAMESPACE) || true > /dev/null
	@sleep 1
	@APP=$(APP) KUBE_NAMESPACE=$(NAMESPACE) bash sh/update-kube-object.sh ./test/fixtures/secrets > /dev/null
	@APP=$(APP) KUBE_NAMESPACE=$(NAMESPACE) bash sh/update-kube-object.sh ./test/fixtures/configmaps > /dev/null
	@kubectl --namespace=$(NAMESPACE) get secret $(APP)-supersecret > /dev/null
	@kubectl --namespace=$(NAMESPACE) get configmap $(APP)-testfile > /dev/null

clean-common-make:
	$(call INFO, "cleaning up testing namespace $(NAMESPACE)")
	@kubectl delete namespace $(NAMESPACE) 2> /dev/null || true  > /dev/null
	@sleep 1

test-common-pants: install-circle-pants
	$(call INFO, "testing common pants")
	@$(HOME)/bin/pants version > /dev/null

test-common-kube:
	$(call INFO, "testing common kube")
	@echo $(KUBE_NAMESPACE)

test-common-docker:
	$(call INFO, "testing common docker")
ifdef CIRCLE_BUILD_NUM
	@test "$(CIRCLE_BUILD_NUM)" = "$(BUILD_NUM)"
endif
test-common-docker: push-circle

test-common-go:
	$(call INFO, "testing common go")
test-common-go: deps-coverage
