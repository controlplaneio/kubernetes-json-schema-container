# Kubernetes JSON Schemas Container

## About

Putting [Kubernetes JSON Schemas][kubernetes_schemas_repo] into containers for easy use when building containers.

[kubernetes_schemas_repo]: https://github.com/instrumenta/kubernetes-json-schema.git

## Usage

To use the schemas in your containers you can add the following:

```Dockerfile
COPY --from=controlplane/kubernetes-json-schema:master-standalone / /some/location
```

Just change the tag from `master-standalone` to whichever schema you want, preferably something version pinned to avoid breaking changes.

## Tracking the build of these images

In an attempt to help track how images have been built there are various Annotations/Labels to provide relevant information.

This isn't intended to be a comprehensive solution but it's a start.

The `ci_link` label is not very precise, as GitHub Actions doesn't make run IDs very clear, and will only link to the overall workflow.
Additional details such as the `revision` and `created` tags should help you narrow down your search for which run built and pushed that specific image tag.

Note: *I have looked around for methods of getting a more precise link for a specific action's output but haven't had much luck.
There have been some support posts but nothing has worked so far.
If you can demonstrate a method of producing a link to an action's own output from within said action please file an issue with details.*

## Manually building containers

You can simply run `build.sh` if you have `git`, `jq`, `curl`, and probably also GNU user-land utilities (e.g. GNU's version of `date` rather than the BSD version).

You can run `build.sh true` to try building all version tags but it will still skip existing tags.

To not skip existing tags you can run `SKIP_EXISTING=false build.sh`.

You can add `true` like above to build all and not skip existing tags.

Here is an example of how to manually build images using the bare-bones `Dockerfile`:

```sh
docker build ./kubernetes-json-schema/v1.16.0-standalone -f Dockerfile -t controlplane/kubernetes-json-schema:v1.16.0-standalone --build-arg DATETIME="$(date --rfc-3339=seconds | sed 's/ /T/')"
# The DATETIME arg is used for the OCI Annotation `org.opencontainers.image.created` which should be an RFC-3339 date-time
# the GNU Date tool doesn't include date-time specifically so sed is used here to insert the T
# If you don't care about the tag feel free to replace it with "N/A"
```

If you manually run `docker build` you will also need to manually clone the schema repo and make sure it's up to date.
Also you wont need the additional dependencies like `jq` or `curl`.

There are additional build args you can modify depending on your requirements or just simply adapt the `Dockerfile` for your needs.

## Thoughts for potential future changes

* Automatically create new `Dockerfile`s
  * There is potential to move to CI that will automatically create and commit new `Dockerfile`s from a template based on new versions.
  * The benefit of this is it can make it easier to inspect the container.
  * The negative is it's quite a lot of faff.
  * Also it still wont lead to Docker Hub Automated builds because new tags for DH Automated builds must be added manually
* Ensure tags wont change underneath people
  * We need to do more investigation into if the schemas can be changed retroactively.
  * In theory with semantic versioning they shouldn't or at least won't have breaking changes but that is yet to be confirmed.
* Confirm dependencies
  * The `build.sh` script requires `git`, `jq`, `curl`, and probably GNU user-land tooling
  * `git` will remain a requirement and `jq` is by far the easiest way to work with JSON from the Docker Hub API
  * We can confirm GNU tooling is required and potentially try move to a POSIX compliant version of `date` or other utilities
  * We can potentially check for `curl` or `wget` and change the script to use either but it's not much of a requirement to ask people to use `curl`
