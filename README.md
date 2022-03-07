kube to GCE DNS
----
Register kube public services in a gce domain with kube namespaces.

[![Unsupported](https://img.shields.io/badge/Pantheon-Unsupported-yellow?logo=pantheon&color=FFDC28)](https://pantheon.io/docs/oss-support-levels#unsupported)

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

