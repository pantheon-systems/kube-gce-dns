APP := example-app
PROJECT := $$GOOGLE_PROJECT

PYTHON_PACKAGE_NAME := example-app
# TEST_RUNNER := ...


include devops/make/common.mk
include devops/make/common-kube.mk
include devops/make/common-docker.mk
include devops/make/common-python.mk

check-deployment-status:
	@timeout 120 kubectl rollout status deployment/$(APP) --namespace=$(KUBE_NAMESPACE) \
		| grep 'successfully' && echo 'Deploy succeeded.' && exit 0 \
		|| echo 'Deploy unsuccessful. Investigate.' && exit 1

deploy: push-circle update-configmaps update-services update-deployment

update-services:
	test "$(KUBE_NAMESPACE)"
	kubectl apply --namespace=$(KUBE_NAMESPACE) -f devops/k8s/service.template.yml

update-deployment:
	test "$(IMAGE)" \
		-a "$(REPLICAS)" \
		-a "$(BUILD_NUM)" \
		-a "$(KUBE_NAMESPACE)"
	sed -e "s#__IMAGE__#$(IMAGE)#" \
		-e "s#__REPLICAS__#$(REPLICAS)#" \
		-e "s/__BUILD__/$(BUILD_NUM)/" \
		devops/k8s/deployment.template.yml \
		| kubectl apply --namespace=$(KUBE_NAMESPACE) -f -

