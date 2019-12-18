#!/usr/bin/env bash
# set -euxo pipefail

SCHEMA_REPO="https://github.com/instrumenta/kubernetes-json-schema.git"
REPO_OUTPUT="./kubernetes-json-schema"
IMAGE="06kellyjac/tmp"

# Default to false
BUILD_ALL_VERSIONS=${1:-false}
# Default to true
SKIP_EXISTING=${SKIP_EXISTING:-true}

if [ -n "$GITHUB_REPOSITORY" ] && [ -n "$GITHUB_SHA" ]; then
	CI_LINK="https://github.com/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}/checks"
fi

cleanup() {
	if [ -d "$REPO_OUTPUT" ]; then
		rm -rf "$REPO_OUTPUT"
	fi
}

clone_schemas() {
	git clone "$SCHEMA_REPO" "$REPO_OUTPUT"
	echo
}

list_standalone_versions() {
	find . -type d -name "*-standalone*"
}

sort_semver() {
	sed "/-/!{s/$/_/}" | sort -Vr | sed "s/_$//"
}

extract_dir() {
	REGEX_DIR="v\d+\.\d+\.\d+.*|master.*"
	grep -Po "$REGEX_DIR"
}

extract_version() {
	REGEX_VERSION="v\d+\.\d+\.\d+"
	grep -Po "$REGEX_VERSION"
}

# Function agument has a fallback default
# shellcheck disable=SC2120
latest_three_minor() {
	# Accept first argument or default to any didgets
	MAJOR="${1:-\d}"
	REGEX_MINOR="v${MAJOR}+\.\d+"
	grep -Po "$REGEX_MINOR" | uniq | sed 3q
}

matching_patches() {
	all="$1"
	latest=$(echo "$2" | tr '\n' '|')
	# Removing the additional '|' at the end
	latest="${latest%?}"

	echo "$all" | grep -P "$latest"
}

get_docker_tags() {
	URL="https://hub.docker.com/v2/repositories/${IMAGE}/tags"
	RESPONSE=$(curl -s "$URL")
	echo "$RESPONSE" | jq --raw-output ".results[].name"
}

docker_contain() {
	CONTEXT="$1"
	TAG="$2"
	DATETIME="$(date --rfc-3339=seconds | sed 's/ /T/')"

	add_buildarg() {
		KEY="$1"
		VALUE="$2"
		BUILD_ARGS=" --build-arg $KEY='${VALUE}'$BUILD_ARGS"
	}
	
	get_sha() {
		if [ -n "$GITHUB_SHA" ]; then
			echo "$GITHUB_SHA"
		else
			git rev-parse HEAD
		fi
	}

	BUILD_ARGS=""

	add_buildarg "DATETIME" "$DATETIME"

	add_buildarg "SHA" "$(get_sha)"

	if [ -n "$CI_LINK" ]; then
		add_buildarg "CI_LINK" "$CI_LINK"
	fi

	echo "$BUILD_ARGS"
	eval "docker build $CONTEXT -f Dockerfile -t $TAG $BUILD_ARGS"
	echo "Success"
	echo "Pushing image '$TAG' to Docker Hub ..."
	docker push "$TAG"
	echo "Success"
	echo
}

build_missing_docker_tags() {
	DOCKER_TAGS="$1"
	VERSIONS="$2"

	for VERSION in $VERSIONS; do
		is_match=false
		for TAG in $DOCKER_TAGS; do
			if [ "$TAG" = "$VERSION" ]; then
				is_match=true
			fi
		done

		if $is_match && $SKIP_EXISTING; then
			echo "Tag '$VERSION' already exists on image '$IMAGE', skipping ..."
			echo
		else
			if $is_match && ! $SKIP_EXISTING; then
				echo "Skip building existing existing image, overridden, not skipping ..."
			fi
			echo "Tag '$VERSION' does not exist on image '$IMAGE', building ..."
			FULL_TAG="${IMAGE}:${VERSION}"
			docker_contain "$REPO_OUTPUT/${VERSION}" "$FULL_TAG"
		fi
	done
}

# A pinned build of master for existing kubesec use
build_pinned_legacy_version() {
	DOCKER_TAGS="$1"
	PINNED_TAG="kubesec_v2_pinned"
	COMMIT_SHA="8aa572595b98d73b2b9415ca576f78e163381b10"

	( cd "$REPO_OUTPUT" && git branch && git checkout "$COMMIT_SHA" --quiet && git branch && echo "" )

	is_match=false
	for TAG in $DOCKER_TAGS; do
		if [ "$TAG" = "$PINNED_TAG" ]; then
			is_match=true
			return
		fi
	done

	if $is_match && $SKIP_EXISTING; then
		echo "Tag '$PINNED_TAG' already exists on image '$IMAGE', skipping ..."
		echo
	else
		if $is_match && ! $SKIP_EXISTING; then
			echo "Skip building existing existing image, overridden, not skipping ..."
		fi
		echo "Tag '$PINNED_TAG' does not exist on image '$IMAGE', building ..."
		FULL_TAG="${IMAGE}:${PINNED_TAG}"
		docker_contain "$REPO_OUTPUT/master-standalone" "$FULL_TAG"
	fi
}


trap cleanup EXIT SIGINT SIGQUIT
cleanup
clone_schemas

SORTED_SEMVER=$(list_standalone_versions | sort_semver)
VERSIONS_DIR=$(echo "$SORTED_SEMVER" | extract_dir)
VERSIONS=$(echo "$SORTED_SEMVER" | extract_version)

if ! $BUILD_ALL_VERSIONS; then
	VERSIONS=$(echo "$VERSIONS" | latest_three_minor)
fi

# Attach master as a required version to build
VERSIONS="$VERSIONS
master"

TARGET_VERSIONS=$(matching_patches "$VERSIONS_DIR" "$VERSIONS")
echo "Target Versions:"
echo "${TARGET_VERSIONS}"
echo

DOCKER_TAGS=$(get_docker_tags)
build_missing_docker_tags "$DOCKER_TAGS" "$TARGET_VERSIONS"

build_pinned_legacy_version "$DOCKER_TAGS"
