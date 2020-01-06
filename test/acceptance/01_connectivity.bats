#!/usr/bin/env bash

load '_helper'

setup() {
  _global_setup
}

teardown() {
  _global_teardown
}

@test "returns help text" {

  run ./build.sh --help

  [ "${status}" == 2 ]

  assert_output --partial "Usage:"
}

