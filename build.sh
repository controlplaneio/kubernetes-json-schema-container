#!/usr/bin/env bash
#
# Templating with Yeoman
#
# Jack Kelly, 2019-12-20 15:11:57
# jack@control-plane.io
#
## Usage: %SCRIPT_NAME% [options] filename
##
## Options:
##   --push                      Push Docker container image
##
##   --debug                     Enable debug mode
##   -v, --version               Print version
##   -h, --help                  Display this message
##

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # exit on error or pipe failure
  set -eo pipefail

  # error on unset variable
  if test "${BASH}" = "" || "${BASH}" -uc 'a=();true "${a[@]}"' 2>/dev/null; then
    set -o nounset
  fi

  # error on clobber
  set -o noclobber

  # disable passglob
  shopt -s nullglob globstar
fi

# resolved directory and self
declare -r DIR=$(cd "$(dirname "${0}")" && pwd)
declare -r THIS_SCRIPT="${DIR}/$(basename "${0}")"

SCHEMA_REPO="https://github.com/instrumenta/kubernetes-json-schema.git"
REPO_OUTPUT="./kubernetes-json-schema"

IMAGE="controlplane/kubernetes-json-schema"

IS_DOCKER_PUSH=""

# Default to false
BUILD_ALL_VERSIONS=${1:-false}
# Default to true
SKIP_EXISTING=${SKIP_EXISTING:-true}

#if [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_SHA}" ]; then
if [[ "${GITHUB_REPOSITORY:-}" != "" ]] && [[ "${GITHUB_SHA:-}" != "" ]]; then
	CI_LINK="https://github.com/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}/checks"
fi

main() {

  handle_arguments "$@"

  trap cleanup EXIT SIGINT SIGQUIT
  cleanup
  clone_schemas

  SORTED_SEMVER=$(list_standalone_versions | sort_semver)
  VERSIONS_DIR=$(echo "${SORTED_SEMVER}" | extract_dir)
  VERSIONS=$(echo "${SORTED_SEMVER}" | extract_version)

  if [[ "${IS_BUILD_ALL_VERSIONS:-}" != "" ]]; then
#  if ! ${BUILD_ALL_VERSIONS}; then
    VERSIONS=$(echo "$VERSIONS" | latest_three_minor)
  fi

  # Attach master as a required version to build
  VERSIONS="${VERSIONS}
  master"

  TARGET_VERSIONS=$(matching_patches "$VERSIONS_DIR" "$VERSIONS")
  info "Target Versions:"
  info "${TARGET_VERSIONS}"
  echo

  DOCKER_TAGS=$(get_docker_tags)
  build_missing_docker_tags "$DOCKER_TAGS" "$TARGET_VERSIONS"

  build_pinned_legacy_version "$DOCKER_TAGS"
}

handle_arguments() {
  parse_arguments "${@:-}"
  validate_arguments "${@:-}"
}

parse_arguments() {
  local CURRENT_ARG
  local NEXT_ARG
  local SPLIT_ARG
  local COUNT=0

  if [[ "${#}" == 1 && "${1:-}" == "" ]]; then
    return 0
  fi

  while [[ "${#}" -gt 0 ]]; do
    CURRENT_ARG="${1}"

    COUNT=$((COUNT + 1))
    if [[ "${COUNT}" -gt 100 ]]; then
      error "Too many arguments or '${CURRENT_ARG}' is unknown"
    fi

    IFS='=' read -ra SPLIT_ARG <<<"${CURRENT_ARG}"
    if [[ ${#SPLIT_ARG[@]} -gt 1 ]]; then
      CURRENT_ARG="${SPLIT_ARG[0]}"
      unset 'SPLIT_ARG[0]'
      NEXT_ARG="$(printf "%s=" "${SPLIT_ARG[@]}")"
      NEXT_ARG="${NEXT_ARG%?}"
    else
      shift
      NEXT_ARG="${1:-}"
    fi

    case ${CURRENT_ARG} in
      --description)
        not_empty_or_usage "${NEXT_ARG:-}"
        DESCRIPTION="${NEXT_ARG}"
        shift
        ;;
      # ---
      --config)
        not_empty_or_usage "${NEXT_ARG:-}"
        CONFIG_FILE="${NEXT_ARG}"
        shift
        ;;
      -h | --help) usage ;;
      -v | --version)
        get_version
        exit 0
        ;;
      --debug)
        DEBUG=1
        set -xe
        ;;
      --dry-run) DRY_RUN=1 ;;
      --)
        EXTENDED_ARGS="${@}"
        break
        ;;
      -*) usage "${CURRENT_ARG}: unknown option" ;;
      *) ARGUMENTS+=("${CURRENT_ARG}") ;;
    esac
  done
}

validate_arguments() {
#  FILENAME="${ARGUMENTS[0]:-}" || true

#  [[ -z "${FILENAME:-}" ]] && usage "Filename required"

  :
}

# helper functions

usage() {
  [ "${*}" ] && echo "${THIS_SCRIPT}: ${COLOUR_RED}${*}${COLOUR_RESET}" && echo
  sed -n '/^##/,/^$/s/^## \{0,1\}//p' "${THIS_SCRIPT}" | sed "s/%SCRIPT_NAME%/$(basename "${THIS_SCRIPT}")/g"
  exit 2
} 2>/dev/null

success() {
  [ "${*:-}" ] && RESPONSE="${*}" || RESPONSE="Unknown Success"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_GREEN}${RESPONSE}${COLOUR_RESET}"
} 1>&2

info() {
  [ "${*:-}" ] && INFO="${*}" || INFO="Unknown Info"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_WHITE}${INFO}${COLOUR_RESET}"
} 1>&2

warning() {
  [ "${*:-}" ] && ERROR="${*}" || ERROR="Unknown Warning"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_RED}${ERROR}${COLOUR_RESET}"
} 1>&2

error() {
  [ "${*:-}" ] && ERROR="${*}" || ERROR="Unknown Error"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_RED}${ERROR}${COLOUR_RESET}"
  exit 3
} 1>&2

error_env_var() {
  error "${1} environment variable required"
}

log_message_prefix() {
  local TIMESTAMP
  local THIS_SCRIPT_SHORT=${THIS_SCRIPT/${DIR}/.}
  TIMESTAMP="[$(date +'%Y-%m-%dT%H:%M:%S%z')]"
  tput bold 2>/dev/null
  echo -n "${TIMESTAMP} ${THIS_SCRIPT_SHORT}: "
}


# ---

cleanup() {
	if [ -d "${REPO_OUTPUT}" ]; then
		rm -rf "${REPO_OUTPUT}"
	fi
}

clone_schemas() {
	git clone "${SCHEMA_REPO}" "${REPO_OUTPUT}"
	echo
}

list_standalone_versions() {
	find . -type d -name "*-standalone*"
}

sort_semver() {
	sed "/-/!{s/$/_/}" | sort -Vr | sed "s/_$//"
}

extract_dir() {
	local REGEX_DIR="v\d+\.\d+\.\d+.*|master.*"
	grep -Po "${REGEX_DIR}"
}

extract_version() {
	local REGEX_VERSION="v\d+\.\d+\.\d+"
	grep -Po "${REGEX_VERSION}"
}

# Function argument has a fallback default
# shellcheck disable=SC2120
latest_three_minor() {
	# Accept first argument or default to any digits
	local MAJOR="${1:-\d}"
	local REGEX_MINOR="v${MAJOR}+\.\d+"
	grep -Po "${REGEX_MINOR}" | uniq | sed "3q"
}

matching_patches() {
	local ALL="$1"
	local LATEST=$(echo "$2" | tr '\n' '|')
	# Removing the additional '|' at the end
	local LATEST="${LATEST%?}"

	echo "${ALL}" | grep -P "${LATEST}"
}

get_docker_tags() {
	local URL="https://hub.docker.com/v2/repositories/${IMAGE}/tags"
	local RESPONSE=$(curl -s "${URL}")

	echo "${RESPONSE}" | jq --raw-output ".results[].name"
}

docker_build_and_push() {
	CONTEXT="$1"
	TAG="$2"
	DATETIME="$(date --rfc-3339=seconds | sed 's/ /T/')"

	add_buildarg() {
		local KEY="$1"
		local VALUE="$2"
		BUILD_ARGS=" --build-arg ${KEY}='${VALUE}'${BUILD_ARGS}"
	}

	get_sha() {
		if [ -n "${GITHUB_SHA:-}" ]; then
			echo "${GITHUB_SHA}"
		else
			git rev-parse HEAD
		fi
	}

	BUILD_ARGS=""

	add_buildarg "DATETIME" "${DATETIME}"

	add_buildarg "SHA" "$(get_sha)"

	if [ -n "${CI_LINK:-}" ]; then
		add_buildarg "CI_LINK" "${CI_LINK}"
	fi

	info "Build args: ${BUILD_ARGS}"
	eval "docker build ${CONTEXT} -f Dockerfile -t ${TAG} ${BUILD_ARGS}"
	success "Success"

  if [[ "${IS_DOCKER_PUSH:-}" != "" ]]; then
    info "Pushing image '$TAG' to Docker Hub ..."
    docker push "$TAG"
  fi

	success "Success"
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
			docker_build_and_push "$REPO_OUTPUT/${VERSION}" "$FULL_TAG"
		fi
	done
}

# A pinned build of master for existing kubesec use
build_pinned_legacy_version() {
	DOCKER_TAGS="$1"
	PINNED_TAG="kubesec_v2_pinned"
	COMMIT_SHA="8aa572595b98d73b2b9415ca576f78e163381b10"

	( cd "$REPO_OUTPUT" && git branch && git checkout "$COMMIT_SHA" --quiet && git branch && echo )

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
		docker_build_and_push "$REPO_OUTPUT/master-standalone" "$FULL_TAG"
	fi
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

  export CLICOLOR=1
  export TERM="${TERM:-xterm-color}"
  export COLOUR_BLACK=$(tput setaf 0 :-"" 2>/dev/null)
  export COLOUR_RED=$(tput setaf 1 :-"" 2>/dev/null)
  export COLOUR_GREEN=$(tput setaf 2 :-"" 2>/dev/null)
  export COLOUR_YELLOW=$(tput setaf 3 :-"" 2>/dev/null)
  export COLOUR_BLUE=$(tput setaf 4 :-"" 2>/dev/null)
  export COLOUR_MAGENTA=$(tput setaf 5 :-"" 2>/dev/null)
  export COLOUR_CYAN=$(tput setaf 6 :-"" 2>/dev/null)
  export COLOUR_WHITE=$(tput setaf 7 :-"" 2>/dev/null)
  export COLOUR_RESET=$(tput sgr0 :-"" 2>/dev/null)

  main "${@}"
fi
