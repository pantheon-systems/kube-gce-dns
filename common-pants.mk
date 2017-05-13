# install and configure pants on circle-ci
#
# The following ENV vars must be set before calling this script:
#
#   GITHUB_TOKEN          # Github Personal Access token to read the private repository
#
# Optional:
#   PANTS_VERSION         # Version of pants to install.
#   PANTS_INCLUDE         # Services for pants to include. Default is all.
#
FETCH_URL := "https://github.com/gruntwork-io/fetch/releases/download/v0.1.0/fetch_linux_amd64"
# Installs greater than 0.1.3 unless overridden.
PANTS_VERSION := ">=0.1.5"
FLAGS := --update-onebox=false
ifdef PANTS_INCLUDE
  FLAGS += --include $(PANTS_INCLUDE)
endif

## append to the global task
deps-circle:: install-circle-pants

install-circle-fetch:
ifeq (,$(wildcard $(HOME)/bin/fetch ))
	$(call INFO, "installing 'fetch' tool")
	@curl -s -L $(FETCH_URL) -o $(HOME)/bin/fetch > /dev/null
	@chmod 755 $(HOME)/bin/fetch > /dev/null
else
	$(call INFO, "'fetch' tool already installed")
endif

install-circle-pants: install-circle-fetch
ifndef GITHUB_TOKEN
	$(call ERROR, "This task needs a GITHUB_TOKEN environment variable")
endif
	$(call INFO, "Installing pants version: $(PANTS_VERSION)")
	@fetch --repo="https://github.com/pantheon-systems/pants" \
      --tag=$(PANTS_VERSION) \
      --release-asset="pants-linux" \
      --github-oauth-token=$$GITHUB_TOKEN \
      $(HOME)/bin > /dev/null
	@mv $(HOME)/bin/pants-linux $(HOME)/bin/pants > /dev/null
	@chmod 755 $(HOME)/bin/pants > /dev/null

init-circle-pants:: ## initializes pants sandbox, updates sandbox if it exists
	$(call INFO, "Initializing sandbox \'$(KUBE_NAMESPACE)\' with flags \'$(FLAGS)\'")
	@pants sandbox init --sandbox=$(KUBE_NAMESPACE) $(FLAGS) 2> /dev/null || pants sandbox update --sandbox=$(KUBE_NAMESPACE) $(FLAGS)

init-circle-pants:: label-ci-ns

# Labels the sandbox namespace so that garbage collection can delete namespaces
# or PRs that no longer exist.
label-ci-ns:
ifdef CIRCLECI
	$(call INFO, "Adding labels to namespace: $(KUBE_NAMESPACE)")
	@kubectl label --overwrite ns $(KUBE_NAMESPACE) time="$(shell date "+%Y-%m-%d---%H-%M-%S")" repo=$$CIRCLE_PROJECT_REPONAME pr=$$CI_PULL_REUQEST
endif
