#!/usr/bin/env bash

mode="${1:-release}"
variant="${2:-weval}"

exec `dirname $0`/build-engine.sh $mode $variant rebuild
