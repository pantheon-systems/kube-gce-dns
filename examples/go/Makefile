# The project base or root Makefile. We need to specify project variables here,
# and can also use this as a place to add custom Make commands.

# APP is used by several common makefiles, e.g. for the name of the
# container, and the name of the binary in the case of a Go project.
# It should also match the name of the app found in the deployment and
# service Kubernetes templates, which are explained below in the
# `update-deployment` and `update-services` command comments.
APP := example-app

# Including the common files will automatically cause their hooks to be run
# when the "parent" make command is executed. See circle.yml for more explanation.
include devops/make/common.mk
include devops/make/common-go.mk
include devops/make/common-kube.mk
include devops/make/common-pants.mk
include devops/make/common-docker.mk

# REPLICAS is the number of instances of your application (pods) that
# Kubernetes will run. This value is injected into the deployment template.
# Some applications need many replicas to be able to provide their service
# at scale, but some should only be running a single instance.
#
# Provide a sensible default value.
REPLICAS := 1
ifeq ($(KUBE_NAMESPACE), production)
	# Let's run 3 replicas in production. For a real app we'd want to choose
	# an appropriate number based on estimated and actual load on the application.
	# This can be tweaked as needed after a service is deployed and matures.
	REPLICAS := 3
else ifeq ($(KUBE_NAMESPACE), template-sandbox)
	# In the `template-sandbox`, we want an environment that is as representative
	# as possible, so it's a good idea to have 2 replicas if the app runs with > 1
	# in production, and only 1 replica if it's just 1 in prod. We definitely don't
	# need > 2 replicas running in template-sandbox - when the `pants` tool
	# does a clone from the template to a sandbox, it will always reduce the number
	# of replicas to <= 2.
	REPLICAS := 2
endif

# None of the common makefiles define what happens on a `make deploy`, so
# we take control of that here.
#
# Step 1 is `push-circle`, which is handled by `common-docker.mk`,
# and will build the Docker image, login to the container registry (Quay.io),
# and push the resulting image up to the registry. In order for this step
# to succeed, the QUAY_USER and QUAY_PASSWD variables need to be set in
# the Circle project settings. These can be copied from another project.
#
# Step 2 is `update-configmaps`, which is a command provided by
# `common-kube.mk`. It updates the Kube configMaps using automatic discovery.
# Your application should provide these files for configuration purposes.
# We have example configMaps in this project, see `devops/k8s/configmaps`.
# You can see how they are mounted by reading `devops/k8s/deployment.template.yml`.
# The `update-configmaps` command below must be listed before `update-deployment`,
# since the new deployment probably relies on the new configMaps, and the app
# might not start if they aren't deployed in the correct order.
#
# - There's extensive documentation on how to structure these here:
#   https://github.com/pantheon-systems/common_makefiles#update-configmaps
#
# Step 3 is `update-services` which is defined and described below.
# Step 4 is `update-deployment`, which is defined and described below.
deploy: push-circle update-configmaps update-services update-deployment

# We keep a deployment template in this repository (in devops/k8s), and this
# `make` step uses `sed` to insert the required variables into the template,
# and then passes the result to `kubectl apply`, effectively triggering a new
# deploy of our application. Read the comments in `devops/k8s/deployment.template.yml`
# for more info.
update-deployment:
	# `sed` is a very bare-bones templating system. We use `test` to ensure that
	# all the required variables are present, before passing it to kubectl,
	# to ensure that we don't send a broken template to Kube.
	#
	# `IMAGE` is set by `common-docker.mk`.
	# `REPLICAS` is computed above.
	# `BUILD_NUM` is the Circle Build number, and is available automatically.
	# `KUBE_NAMESPACE` is set by common-kube.mk and will be `production` for
	# the master branch. It can also be passed in, as seen in `circle.yml`
	# where we explicitly deploy to `template-sandbox`.
	test "$(IMAGE)" \
		-a "$(REPLICAS)" \
		-a "$(BUILD_NUM)" \
		-a "$(KUBE_NAMESPACE)"
	sed -e "s#__IMAGE__#$(IMAGE)#" \
		-e "s#__REPLICAS__#$(REPLICAS)#" \
		-e "s/__BUILD__/$(BUILD_NUM)/" \
		devops/k8s/deployment.template.yml \
		| kubectl apply --namespace=$(KUBE_NAMESPACE) -f -

# Services define our application's interface to the outside world. See the comments
# in `devops/k8s/service.template.yml` for more info. This step applies any changes
# in our Service definition template.
update-services:
	test "$(KUBE_NAMESPACE)"
	kubectl apply --namespace=$(KUBE_NAMESPACE) -f devops/k8s/service.template.yml

# In our `circle.yml`, we always follow a `deploy` command with `check-deployment-status`,
# this ensures that the deploy was actually successful. By first deploying to the
# `template-sandbox` namespace we can catch certain failures before they deploy to production.
check-deployment-status:
	@timeout 120 kubectl rollout status deployment/$(APP) --namespace=$(KUBE_NAMESPACE) \
		| grep 'successfully' && echo 'Deploy succeeded.' && exit 0 \
		|| echo 'Deploy unsuccessful. Investigate.' && exit 1
