# The Dockerfile is used to specify how Docker builds our container
# image for deployment to the production environment, Google Container
# Engine (Kubernetes). Two useful documentation links are found here:
#
# - https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/
# - https://docs.docker.com/engine/reference/builder/

# We have a list of recommended base images available on the Wiki, please choose
# from one of them if you can, however the policy does allow exceptions on a
# case-by-case basis:
#
# - https://getpantheon.atlassian.net/wiki/display/VULCAN/Pantheon+Docker+Base+Images
#
# "scratch" is a good choice for Go, since apps are self-contained binaries. Note that
# this means you won't be able to shell into the running container, since `/bin/sh` will
# not be there. For more discussion on the appropriate image to choose, see the wiki page above.
FROM scratch

# The name of our app's binary is specified by the APP variable at the
# top of the project's Makefile, and is built by the default common Go makefiles.
# We can just copy the finished executable into the container.
COPY example-app /

# Run the app as the default action for this container. We have to specify the
# entry point as otherwise it'll try use the shell, which fails since this
# container is `FROM scratch`.
#
# This can be overridden by the Kubernetes Deployment template, further discussion
# in the file `devops/k8s/deployment.template.yml`.
ENTRYPOINT ["/example-app"]

# Expose a port so that we can communicate with this container. This is
# only necessary if the app needs to respond to requests - many don't.
# Note that this only exposes the port on a pod level, in order to actually
# connect to the application from the public internet, we'll need to create
# a Kubernetes Service definition, explained in the file `devops/k8s/service.template.yml`.
EXPOSE 4443

# Expose a port for `readiness` and `liveness` probes, see comments in
# `devops/k8s/deployment.template.yml`
EXPOSE 8080
