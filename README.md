# Kubernetes JSON Schemas Container

Putting the Kubernetes JSON Schemas into containers for use in building containers

To use the schemas in your containers you can add the following:

```Dockerfile
COPY --from=controlplane/kubernetes-json-schema:master-standalone / /some/location
```

Just change the tag from `master-standalone` to whichever schema you want.

To see all possible tags look on the [docker hub tags page][docker_hub_tags].

The build script will contain the last 3 semver minor versions as is the kubernetes support policy.
But there will be previously buit versions in the tag list from when they were supported.

[docker_hub_tags]: https://hub.docker.com/r/controlplane/ipfs-cluster-test/tags
