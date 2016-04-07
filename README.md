# kube  to GCE DNS
Register kube public services in a gce domain with kube namespaces.


# Kown issues
* https://github.com/kubernetes/kubernetes/issues/22427
  if you see `util/parsers/parsers.go:30: undefined: parsers.ParseRepositoryTag` it's a known issue with the unversioned kube client in kube version before 1.2. 
  This should be remedied by using the proper docker parsers package: 
  ```
     {
        "ImportPath": "github.com/docker/docker/pkg/mount",
        "Comment": "v1.4.1-4831-g0f5c9d3",
        "Rev": "0f5c9d301b9b1cca66b3ea0f9dec3b5317d3686d"
      },
  ```
