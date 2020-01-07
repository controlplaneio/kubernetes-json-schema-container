#!/usr/bin/env bash
#
# Jack Kelly, 2019-12-20 15:11:57
# jack@control-plane.io
#
## Usage: %SCRIPT_NAME% [options] filename
##
## Options:
##   -v, --version    Print version
##   -h, --help       Display this message
##

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # exit on error or pipe failure
  set -eo pipefail

  # error on unset variable
  # shellcheck disable=SC2016
  if test "${BASH}" = "" || "${BASH}" -uc 'a=();true "${a[@]}"' 2>/dev/null; then
    set -o nounset
  fi

  # error on clobber
  set -o noclobber

  # disable passglob
  shopt -s nullglob globstar
fi

# resolved directory and self
DIR=$(cd "$(dirname "${0}")" && pwd)
export DIR
THIS_SCRIPT="${DIR}/$(basename "${0}")"
export THIS_SCRIPT

NL='
'

SCHEMA_REPO="https://github.com/instrumenta/kubernetes-json-schema.git"
REPO_OUTPUT="./kubernetes-json-schema"

IMAGE="controlplane/kubernetes-json-schema"

# Default to true
SKIP_EXISTING=${SKIP_EXISTING:-true}

if [[ "${GITHUB_REPOSITORY:-}" != "" ]] && [[ "${GITHUB_SHA:-}" != "" ]]; then
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

# Function argument has a fallback default
# shellcheck disable=SC2120
latest_three_minor() {
  # Accept first argument or default to any digits
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
    if [[ "${GITHUB_SHA:-}" != "" ]]; then
      echo "$GITHUB_SHA"
    else
      git rev-parse HEAD
    fi
  }

  BUILD_ARGS=""

  add_buildarg "DATETIME" "$DATETIME"

  add_buildarg "SHA" "$(get_sha)"

  if [[ "${CI_LINK:-}" != "" ]]; then
    add_buildarg "CI_LINK" "$CI_LINK"
  fi

  debug "$BUILD_ARGS"

  cmd "docker build $CONTEXT -f Dockerfile -t $TAG $BUILD_ARGS"
  success "Image built"
  info "Pushing image '$TAG' to Docker Hub ..."
  cmd "docker push $TAG"
  success "Image pushed"
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
      info "Tag '$VERSION' already exists on image '$IMAGE', skipping ..."
      echo
    else
      if $is_match && ! $SKIP_EXISTING; then
        info "Skip building existing existing image, overridden, not skipping ..."
      fi
      info "Tag '$VERSION' does not exist on image '$IMAGE', building ..."
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

  info "Building kubesec pinned image"

  ( cd "$REPO_OUTPUT" && git checkout "$COMMIT_SHA" --quiet && echo )

  is_match=false
  for TAG in $DOCKER_TAGS; do
    if [ "$TAG" = "$PINNED_TAG" ]; then
      is_match=true
      return
    fi
  done

  if $is_match && $SKIP_EXISTING; then
    info "Tag '$PINNED_TAG' already exists on image '$IMAGE', skipping ..."
    echo
  else
    if $is_match && ! $SKIP_EXISTING; then
      info "Skip building existing existing image, overridden, not skipping ..."
    fi
    info "Tag '$PINNED_TAG' does not exist on image '$IMAGE', building ..."
    FULL_TAG="${IMAGE}:${PINNED_TAG}"
    docker_contain "$REPO_OUTPUT/master-standalone" "$FULL_TAG"
  fi
}

main() {

  prepare_colours

  handle_arguments "$@"

  trap cleanup EXIT SIGINT SIGQUIT
  cleanup
  clone_schemas

  SORTED_SEMVER=$(list_standalone_versions | sort_semver)
  VERSIONS_DIR=$(echo "$SORTED_SEMVER" | extract_dir)
  VERSIONS=$(echo "$SORTED_SEMVER" | extract_version)

  if [[ "${IS_BUILD_ALL_VERSIONS:-0}" == 0 ]]; then
    info "Building the last 3 minor versions"
    VERSIONS=$(echo "$VERSIONS" | latest_three_minor)
  else
    info "Building all versions"
  fi

  # Attach master as a required version to build
  VERSIONS="${VERSIONS}${NL}master"

  TARGET_VERSIONS=$(matching_patches "$VERSIONS_DIR" "$VERSIONS")
  info "Target Versions:${NL}${TARGET_VERSIONS}"
  echo

  DOCKER_TAGS=$(get_docker_tags)
  build_missing_docker_tags "$DOCKER_TAGS" "$TARGET_VERSIONS"

  if [[ ${IS_BUILD_KUBESEC_PINNED:-0} == 1 ]]; then
    build_pinned_legacy_version "$DOCKER_TAGS"
  fi
}

# Arguments

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
      -h | --help) usage ;;
      -v | --version)
        get_version
        exit 0
        ;;
      --debug)
        DEBUG=1
        set -xe
        ;;
      --build-all-versions) IS_BUILD_ALL_VERSIONS=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --kubesec | --include-kubesec-pinned) IS_BUILD_KUBESEC_PINNED=1 ;;
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
  if [[ "${*}" == "" ]]; then
    exit 0
  else
    exit 2
  fi
} 2>/dev/null

success() {
  [ "${*:-}" ] && RESPONSE="${*}" || RESPONSE="Unknown Success"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_GREEN}${RESPONSE}${COLOUR_RESET}"
} 1>&2

cmd() {
  [ "${*:-}" ] && CMD="${*}" || CMD="Unknown DEBUG"
  [[ ${DRY_RUN:-0} == 0 ]] && eval "$CMD" || printf "%s\\n" "$(log_message_prefix)${COLOUR_RESET}[${COLOUR_BLUE}DRY RUN${COLOUR_RESET}] ${CMD}${COLOUR_RESET}"
} 1>&2

debug() {
  [ "${*:-}" ] && DEBUG_LOG="${*}" || DEBUG_LOG="Unknown DEBUG"
  [[ ${DEBUG:-0} == 0 ]] || printf "%s\\n" "$(log_message_prefix)${COLOUR_RESET}[${COLOUR_GREEN}DEBUG${COLOUR_RESET}] ${DEBUG_LOG}${COLOUR_RESET}"
} 1>&2

info() {
  [ "${*:-}" ] && INFO="${*}" || INFO="Unknown Info"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_WHITE}${INFO}${COLOUR_RESET}"
} 1>&2

warning() {
  [ "${*:-}" ] && ERROR="${*}" || ERROR="Unknown Warning"
  printf "%s\\n" "$(log_message_prefix)${COLOUR_YELLOW}${ERROR}${COLOUR_RESET}"
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
  # local THIS_SCRIPT_SHORT=${DIR}
  local THIS_SCRIPT_SHORT=${THIS_SCRIPT/${DIR}/.}
  TIMESTAMP="[$(date +'%Y-%m-%dT%H:%M:%S')]"
  tput bold 2>/dev/null
  echo -n "${TIMESTAMP} ${THIS_SCRIPT_SHORT}: "
}

# ---

prepare_colours() {
  export CLICOLOR=1
  export TERM="${TERM:-xterm-color}"

  COLOUR_BLACK=$(tput setaf 0 :-"" 2>/dev/null)
  export COLOUR_BLACK

  COLOUR_RED=$(tput setaf 1 :-"" 2>/dev/null)
  export COLOUR_RED

  COLOUR_GREEN=$(tput setaf 2 :-"" 2>/dev/null)
  export COLOUR_GREEN

  COLOUR_YELLOW=$(tput setaf 3 :-"" 2>/dev/null)
  export COLOUR_YELLOW

  COLOUR_BLUE=$(tput setaf 4 :-"" 2>/dev/null)
  export COLOUR_BLUE

  COLOUR_MAGENTA=$(tput setaf 5 :-"" 2>/dev/null)
  export COLOUR_MAGENTA

  COLOUR_CYAN=$(tput setaf 6 :-"" 2>/dev/null)
  export COLOUR_CYAN

  COLOUR_WHITE=$(tput setaf 7 :-"" 2>/dev/null)
  export COLOUR_WHITE

  COLOUR_RESET=$(tput sgr0 :-"" 2>/dev/null)
  export COLOUR_RESET
}

# ---

main "${@}"
