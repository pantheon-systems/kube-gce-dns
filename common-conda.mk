# Common  Conda Tasks
#
# INPUT VARIABLES
# - TEST_RUNNER: (required) The name of the test runner to execute. Inherited from common-python.mk
# - CONDA_PACKAGE_NAME: (required) The name of your conda package. Used to also name your environment. Defaults to $(PYTHON_PACKAGE_NAME)
# - CONDA_PACKAGE_VERSION: (required) The version of your conda package. Defaults to $(PYTHON_PACKAGE_VERSION)
# - ANACONDA_CLOUD_REPO_TOKEN: (optional) Token to use when reading private conda packages from Anaconda Cloud. This token is required if this package depends on other private packages. For local development this is a personal token connected to your Anaconda Cloud account. For circle this is a token specific to the `pantheon_machines` Anaconda Cloud account and can be found in onelogin secure notes.
# - ANACONDA_CLOUD_DEPLOY_TOKEN: (optional) Required by circle. Token to use when pushing conda packages to Anaconda Cloud. For circle this is a token specific to the `pantheon_machines` Anaconda Cloud account and can be found in onelogin secure notes.
# - ANACONDA_CLOUD_ORGANIZATION: (optional) The name of the organization in Anaconda Cloud. Defaults to `pantheon`
# - CONDA_PACKAGE_LABEL: (optional) The label that will be applied to the conda package on deployment. Defaults to `main`
#
#-------------------------------------------------------------------------------


# The name of the organization account we use in Anaconda Cloud
ANACONDA_CLOUD_ORGANIZATION:=pantheon
# The name that will be used for the conda package and environment.
ifeq (,$(CONDA_PACKAGE_NAME))
CONDA_PACKAGE_NAME:=$(PYTHON_PACKAGE_NAME)
endif
# The version of the conda package.
ifeq (,$(CONDA_PACKAGE_VERSION))
CONDA_PACKAGE_VERSION:=$(PYTHON_PACKAGE_VERSION)
endif
# The label that will be attached to the conda package deployed to Anaconda Cloud
CONDA_PACKAGE_LABEL:=main

MINICONDA_PATH:=~/miniconda2

# Default to exported environment variables if they are set and exist.
# This approach is used in circle and local development
ANACONDA_CLOUD_DEPLOY_TOKEN:=$(shell echo $${ANACONDA_CLOUD_DEPLOY_TOKEN})
ANACONDA_CLOUD_REPO_TOKEN:=$(shell echo $${ANACONDA_CLOUD_REPO_TOKEN})

# FQDN for the anaconda cloud api
ANACONDA_CLOUD_API_FQDN:=api.anaconda.org
# FQDN for conda packages in anaconda cloud
ANACONDA_CLOUD_CONDA_FQDN:=conda.anaconda.org
# FQDN for pypi packages in anaconda cloud (downloading of private pypi packages is a paid feature that we dont currently support)
ANACONDA_CLOUD_PYPI_FQDN:=pypi.anaconda.org

ACTIVE_CONDA_ENVIRONMENT:=$(shell basename $${CONDA_DEFAULT_ENV:-'null'})

## Append tasks to the global tasks
deps:: deps-conda
deps-circle:: deps-conda add-conda-private-channel
build:: build-conda
clean:: clean-conda
setup:: setup-conda

## Assert that there is no active conda environment before allowing certain targets.
_assert-conda-env-not-active:
ifeq ("$(ACTIVE_CONDA_ENVIRONMENT)", "null")
else
	$(error "This target is protected and should not be run inside an active conda environment.\
	The active environment is '$(ACTIVE_CONDA_ENVIRONMENT)'. To deactivate the environment, \
	run:	'source deactivate'	Then try again.")
endif

## Assert that the active conda environment is the one for the project before allowing certain targets.
_assert-conda-env-active:
ifeq ("$(ACTIVE_CONDA_ENVIRONMENT)", "_test")
	$(warning "The active conda environment is '$(ACTIVE_CONDA_ENVIRONMENT)'. Allowing the target to run anyway.")
else
ifneq ($(ACTIVE_CONDA_ENVIRONMENT), $(CONDA_PACKAGE_NAME))
	$(error "The active conda environment is '$(ACTIVE_CONDA_ENVIRONMENT)'. This target expects \
	the active environment to be '$(CONDA_PACKAGE_NAME)'. If you have not yet created \
	the environment, run:	'conda env create'	To activate the environment,\
	run:	'source activate $(CONDA_PACKAGE_NAME)'")
endif
endif

clean-conda:: ## Removes index cache, lock files, tarballs, unused cache packages, and source cache.
	conda clean --all -y

setup-conda:: setup-conda-environment

setup-conda-environment:: _assert-conda-env-not-active ## Attempts to setup the conda virtual environment
ifeq (,$(wildcard ./environment.yml))
	$(error "No environment file found at ./environment.yml")
else
	conda env create || conda env update
endif

build-conda:: ## Build conda package for project with current arch
	conda build --check recipe
	# Runs build, test and post steps
	conda build recipe --no-anaconda-upload

build-conda-deployment-environment:: ## Clone a conda environment into a release environment for dockerization
	conda create --clone $(CONDA_PACKAGE_NAME) -y --prefix ./local --copy

deps-conda:: _assert-conda-env-not-active _conda-install _anaconda-client-install _conda-build-install ## Install conda, anaconda client and conda-build
	conda update -y conda
	conda config --set anaconda_upload no
	conda config --add channels $(ANACONDA_CLOUD_ORGANIZATION)

# Install the anaconda client. Used for making API request to Anaconda Cloud
_anaconda-client-install::
ifeq (, $(shell which anaconda))
	conda install -y anaconda-client
endif

# Install conda-build. A plugin used to build and test conda packages.
_conda-build-install::
ifeq (, $(shell which conda-build))
	conda install -y conda-build
endif

# Download the latest miniconda shell script
_conda-download::
ifeq (, $(shell which conda))
ifeq (, $(wildcard $(MINICONDA_PATH)))
ifeq (Darwin, $(shell uname -s))
	wget https://repo.continuum.io/miniconda/Miniconda2-latest-MacOSX-x86_64.sh -O ~/miniconda2.sh
else
ifeq (x86_64, $(shell uname -m))
	wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh -O ~/miniconda2.sh
else
        wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86.sh -O ~/miniconda2.sh
endif
endif
endif
endif

# Run the miniconda installation script
_conda-install:: _conda-download
ifeq (, $(shell which conda))
ifeq (, $(wildcard $(MINICONDA_PATH)))
	bash ~/miniconda2.sh -b -p $(MINICONDA_PATH)
endif
ifeq (,$(shell grep 'miniconda' ~/.bashrc))
	echo '# Miniconda path added by common-conda.mk' >> ~/.bashrc
	echo 'export PATH=$(MINICONDA_PATH)/bin:$$PATH' >> ~/.bashrc
endif
endif

reset-conda-environment:: _assert-conda-env-not-active ## Reset a conda environment by removing and reinstalling all of its packages.
	conda remove --name $(CONDA_PACKAGE_NAME) --all -y
	conda env update

deploy-conda:: ## Deploys the latest built conda package to Anaconda Cloud
ifeq (, $(ANACONDA_CLOUD_DEPLOY_TOKEN))
	$(error "You asked to deploy a pypi package to '$(ANACONDA_CLOUD_ORGANIZATION)' channel on Anaconda Cloud but `ANACONDA_CLOUD_DEPLOY_TOKEN` was not set.")
else
	conda build -q --user $(ANACONDA_CLOUD_ORGANIZATION) --token $(ANACONDA_CLOUD_DEPLOY_TOKEN) recipe
endif

deploy-conda-pypi:: ## Deploys the latest built pypi package to Anaconda Cloud
ifeq (, $(ANACONDA_CLOUD_DEPLOY_TOKEN))
	$(error "You asked to deploy a pypi package to '$(ANACONDA_CLOUD_ORGANIZATION)' channel on Anaconda Cloud \
	but `ANACONDA_CLOUD_DEPLOY_TOKEN` was not set.")
endif
ifeq (, $(CONDA_PACKAGE_VERSION))
	$(error "You asked to deploy a pypi package to '$(ANACONDA_CLOUD_ORGANIZATION)' channel on Anaconda Cloud \
	but `CONDA_PACKAGE_VERSION` was not set.")
endif
	anaconda --token $(ANACONDA_CLOUD_DEPLOY_TOKEN) upload -u $(ANACONDA_CLOUD_ORGANIZATION) --label $(CONDA_PACKAGE_LABEL) --no-register --force dist/$(CONDA_PACKAGE_NAME)-$(CONDA_PACKAGE_VERSION).tar.gz

test-conda:: ## Run the test suite against a built conda package in an isolated test environment
	conda build --test recipe

# Personal tokens only have access to packages added to the personal account and the pantheon organizations developers security group if the personal account has been added.
regenerate-anaconda-cloud-repo-token:: ## A helper to generate a personal read-only token for downloading private conda packages suitable for local development. If not logged into anaconda client this will present an interactive console
	anaconda auth --remove private_repo || exit 0
	anaconda auth --create --name private_repo --scopes 'conda:download'

add-conda-private-channel:: _assert-conda-env-not-active ## Adds the pantheon private channel for downloading conda packages from Anaconda Cloud
ifeq (,$(ANACONDA_CLOUD_REPO_TOKEN))
	$(error "You asked to add the private '$(ANACONDA_CLOUD_ORGANIZATION)' channel to your conda configuration but `ANACONDA_CLOUD_REPO_TOKEN` was not set.")
else
	conda config --add channels https://$(ANACONDA_CLOUD_CONDA_FQDN)/t/$(ANACONDA_CLOUD_REPO_TOKEN)/$(ANACONDA_CLOUD_ORGANIZATION)
endif

generate-conda-requirements: ## Helper to generate a full dependency tree of this conda environment into a requirements_full.txt
	if [ -a requirements_full.txt ] ; then rm requirements_full.txt ; fi;
	conda env export | grep "\- \w*[=]" | sed "s/\s*[-]\s*//g" | sed "s/\(\w*\)[=]\([0-9][^=]*\)[=]\w[^=]*/\1==\2/g" &> requirements_full.txt

