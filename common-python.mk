# Common  Python Tasks
#
# INPUT VARIABLES
# - PYTHON_PACKAGE_NAME: (required) The name of the python package.
# - TEST_RUNNER: (optional) The name of the python test runner to execute. Defaults to `trial`
# - COVERALLS_TOKEN: (optional) Token to use when pushing coverage to coveralls.
#
#-------------------------------------------------------------------------------


# When no TEST_RUNNER is set the default is trial
ifeq (,$(TEST_RUNNER))
TEST_RUNNER=trial
endif

## Append tasks to the global tasks
deps:: deps-python
deps-circle:: deps-circle-python
lint:: lint-python
test:: test-python lint
test-coverage:: test-coverage-python
test-circle:: test test-circle-python
build:: build-python

build-python:: ## Build python source distribution. How packages are built is determined by setup.py
	python setup.py sdist

# Python tasks
develop-python:: ## Enable setup.py develop mode. Useful for local development. Disable develop mode before installing.
	python setup.py develop

undevelop-python:: ## Disable setup.py develop mode
	python setup.py develop --uninstall

deps-python:: deps-testrunner-python deps-lint-python deps-coverage-python

deps-testrunner-python::
ifeq (, $(shell which $(TEST_RUNNER)))
ifeq ($(TEST_RUNNER), 'trial')
	pip install twisted
else
	pip install $(TEST_RUNNER)
endif
endif

deps-lint-python:: deps-pylint deps-flake8

deps-pylint::
ifeq (, $(shell which pylint))
	pip install pylint
endif

deps-flake8::
ifeq (, $(shell which flake8))
	pip install flake8
endif

deps-coverage-python::
ifeq (, $(shell which coverage))
	pip install coverage
endif

deps-circle-python:: deps-coveralls-python ## Install python dependencies for circle

deps-coveralls-python::

ifdef COVERALLS_TOKEN
ifeq (, $(shell which coveralls))
	pip install coveralls
endif
endif

lint-python:: lint-pylint lint-flake8

# Pylint is a Python source code analyzer which looks for programming errors, helps enforcing a coding standard and sniffs for some code smells
# (as defined in Martin Fowler's Refactoring book). Pylint can also be run against any installed python package which is useful for catching
# misconfigured setup.py files.
lint-pylint:: deps-pylint ## Performs static analysis of your "installed" package. Slightly different rules then flake8. Configuration file '.pylintrc'
	pylint $(PYTHON_PACKAGE_NAME)

# Flake8 is a combination of three tools (Pyflakes, pep8 and mccabe). Flake8 performs static analysis of your uncompiled code (NOT installed packages).
lint-flake8:: deps-flake8 ## Performs static analysis of your code, including adherence to pep8 (pep8) and conditional complexity (McCabe). Configuration file '.flake8'
ifneq ("$(wildcard $(PYTHON_PACKAGE_NAME))", "")
	flake8 --show-source --statistics --benchmark $(PYTHON_PACKAGE_NAME)
else
        # Because flake8 cannot be run against installed packages we emit a warning to allow the global lint target to proceed.
        # This preserves flexibility and enables linting installed packages.
	$(warning "You asked to run flake8 on your source files but could not find them at './$(PYTHON_PACKAGE_NAME)'")
endif

test-python:: test-coverage-python

test-circle-python:: test-coveralls-python

test-coverage-python:: deps-testrunner-python deps-coverage-python ## Run tests and generate code coverage. Configuration file '.coveragerc'
ifdef TEST_RUNNER
	coverage run --branch --source $(PYTHON_PACKAGE_NAME) $(shell which $(TEST_RUNNER)) $(PYTHON_PACKAGE_NAME)
else
	$(error "You asked to run coverage on tests, but neglected to set the TEST_RUNNER environment variable")
endif

coverage-report: ## Display the coverage report. Requires that make test has been run.
	coverage report


test-coveralls-python:: deps-coveralls-python ## run coverage and report to coveralls
ifdef COVERALLS_TOKEN
	coveralls
else
	echo "COVERALLS_TOKEN is not set. Skipping coveralls reporting"
endif

deps-bumpversion-python:
ifeq (, $(shell which bumpversion))
	pip install bumpversion
endif

bumpmicro: bumppatch ## Bump the micro (patch) version of the python package. Configuration file '.bumpversion.cfg'

bumppatch: deps-bumpversion ## Alias for bumpmicro
	bumpversion patch

bumpminor: deps-bumpversion ## Bump the minor version of the python package. Configuration file '.bumpversion.cfg'
	bumpversion minor

bumpmajor: deps-bumpversion ## Bump the major version of the python package. Configuration file '.bumpversion.cfg'
	bumpversion major

.PHONY:: deps-coverage-python deps-circle-python deps-lint-python deps-coveralls-python deps-pylint deps-flake8 test-python test-circle-python test-coveralls-python build-python test-coverage-python coverage-report test-circle test-circle-python bumpmicro bumpminor bumpmajor bumppatch
