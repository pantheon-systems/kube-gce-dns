APP := kube-gce-dns

include devops/make/common.mk
include devops/make/common-go.mk
include devops/make/common-docs.mk
include devops/make/common-docker.mk

cert:
	curl https://curl.haxx.se/ca/cacert.pem -o ca-certificates.crt

deps:: cert

# extend the update-makefiles task to remove files we don't need
update-makefiles::
	prune-common-make

# strip out everything from common-makefiles that we don't want.
prune-common-make:
	@find devops/make -type f \
		-not -name common.mk \
		-not -name common-go.mk \
		-not -name install-go.sh \
		-not -name common-docker.mk \
		-not -name common-docs.mk \
		-delete
	@find devops/make -empty -delete
	@git add devops/make
	@git commit -C HEAD --amend
