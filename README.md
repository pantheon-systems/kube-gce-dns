kube to GCE DNS
----
Register kube public services in a gce domain with kube namespaces.

Usage
-----

Configuration is handled via cli args or env vars:

```
$ ./kube-gce-dns --help
```

## Starting the server
The server can be invoked with the `server` sub command. The option `--domain` and `--project` refer to the DNS domain and the GCE project respectively. The server should connect to the kube api when ran in the `kube-system` namespace, and the `--api` flag is not specified.


Development
-----------

Run `make help` for a list of tasks and their descriptions.

### Testing

Run `make test`

### Running locally
Use kubectl proxy to spin up a proxy to your kube api then run the server with `--api localhost:8001` or whatever port your proxy has been setup on.

### Design & Rationale
When adding/removing services with public IP addresses in kube you might want to also update public dns to those services. This does that for you.

The service is designed to run in the kube-system namespace, and will watch service events for add/remove/update actions, and fire the appropriate calls to the Google DNS service.


Kown issues
----
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
