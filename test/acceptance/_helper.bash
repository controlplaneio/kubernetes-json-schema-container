#!/usr/bin/env bash

load './bin/bats-support/load'
load './bin/bats-assert/load'

_global_setup() {
  [ ! -f "${BATS_PARENT_TMPNAME}.skip" ] || skip "skip remaining tests"
}

_global_teardown() {
  if [ ! -n "${BATS_TEST_COMPLETED}" ]; then
    touch "${BATS_PARENT_TMPNAME}.skip"
  fi
}

# ---

try () {
    try-limit 0 "${@}"
}

try-limit () {
    local LIMIT=$1;
    local COUNT=1;
    local RETURN_CODE;
    shift;
    local COMMAND="${@:-}";
    if [[ "${COMMAND}" == "" ]]; then
        echo "At least two arguments required (limit, command)" 1>&2;
        return 1;
    fi;
    function _try-limit-output ()
    {
        printf "\n$(date) (${COUNT}): %s - " "${COMMAND}" 1>&2
    };
    echo "Limit: ${LIMIT}. Trying command: ${COMMAND}";
    _try-limit-output;
    until echo "${COMMAND}" | source /dev/stdin; do
        RETURN_CODE=$?;
        echo "Return code: ${RETURN_CODE}";
        if [[ "${LIMIT}" -gt 0 && "${COUNT}" -ge "${LIMIT}" ]]; then
            printf "\nFailed \`${COMMAND}\` after ${COUNT} iterations\n" 1>&2;
            return 1;
        fi;
        COUNT=$((COUNT + 1));
        _try-limit-output;
        if [[ "${_TRY_LIMIT_BACKOFF:-}" != "" ]]; then
            sleep $(((COUNT * _TRY_LIMIT_BACKOFF) / 10));
        else
            sleep ${_TRY_LIMIT_SLEEP:-0.3};
        fi;
    done;
    RETURN_CODE=$?;
    if [[ "${COUNT}" == 1 ]]; then
        echo;
    fi;
    echo "Completed \`${COMMAND}\` after ${COUNT} iterations" 1>&2;
    unset _TRY_LIMIT_SLEEP _TRY_LIMIT_BACKOFF;
    return ${RETURN_CODE}
}
