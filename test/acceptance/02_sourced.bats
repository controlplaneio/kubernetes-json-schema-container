#!/usr/bin/env bash

load '_helper'

setup() {
  _global_setup
}

teardown() {
  _global_teardown
}

@test "has main function" {

  source ./build.sh

  [ "${SCHEMA_REPO}" != "" ]
}

