#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

###
# DuckerUp parameters are specified with env variables

# Num of cotainers that ducktape will prepare for tests
IGNITE_NUM_CONTAINERS=${IGNITE_NUM_CONTAINERS:-11}

# Image name to run nodes
default_image_name="ducker-ignite-openjdk-8"
IMAGE_NAME="${IMAGE_NAME:-$default_image_name}"

###
# DuckerTest parameters are specified with options to the script

# Path to ducktests
TC_PATHS="./ignitetest/"
# Global parameters to pass to ducktape util with --global param
GLOBALS="{}"
# Ducktests parameters to pass to ducktape util with --parameters param
PARAMETERS="{}"

###
# RunTests parameters
# Force flag:
# - skips ducker-ignite compare step;
# - sends to duck-ignite scripts.
FORCE=

usage() {
    cat <<EOF
run_tests.sh: useful entrypoint to ducker-ignite util

Usage: ${0} [options]

The options are as follows:
-h|--help
    Display this help message

-p|--param
    Use specified param to inject in tests. Could be used multiple times.

    ./run_tests.sh --param version=2.8.1

-g|--global
    Use specified global param to pass to test context. Could be used multiple times.

    List of supported global parameters:
    - project: is used to build path to Ignite binaries within container (/opt/PROJECT-VERSION)
    - ignite_client_config_path: abs path within container to Ignite client config template
    - ignite_server_config_path: abs path within container to Ignite server config template
    - jvm_opts: array of JVM options to use when Ignite node started

-t|--tc-paths
    Path to ducktests. Must be relative path to 'IGNITE/modules/ducktests/tests' directory

EOF
    exit 0
}


die() {
    echo "$@"
    exit 1
}

_extend_json() {
    python - "$1" "$2" <<EOF
import sys
import json

[j, key_val] = sys.argv[1:]
[key, val] = key_val.split('=', 1)
j = json.loads(j)
j[key] = val

print(json.dumps(j))

EOF
}

duck_add_global() {
  GLOBALS="$(_extend_json "${GLOBALS}" "${1}")"
}

duck_add_param() {
  PARAMETERS="$(_extend_json "${PARAMETERS}" "${1}")"
}

while [[ $# -ge 1 ]]; do
    case "$1" in
        -h|--help) usage;;
        -p|--param) duck_add_param "$2"; shift 2;;
        -g|--global) duck_add_global "$2"; shift 2;;
        -t|--tc-paths) TC_PATHS="$2"; shift 2;;
        -f|--force) FORCE=$1; shift;;
        *) break;;
    esac
done

if [[ "$IMAGE_NAME" == "$default_image_name" ]]; then
    "$SCRIPT_DIR"/ducker-ignite build "$IMAGE_NAME" || die "ducker-ignite build failed"
else
    echo "[WARN] Used non-default image $IMAGE_NAME. Be sure you use actual version of the image. " \
         "Otherwise build it with 'ducker-ignite build' command"
fi

if [ -z "$FORCE" ]; then
    # If docker image changed then restart cluster (down here and up within next step)
    "$SCRIPT_DIR"/ducker-ignite compare "$IMAGE_NAME" || die "ducker-ignite compare failed"
fi

# Up cluster if nothing is running
if "$SCRIPT_DIR"/ducker-ignite ssh | grep -q '(none)'; then
    # do not quote FORCE as bash recognize "" as input param instead of image name
    "$SCRIPT_DIR"/ducker-ignite up $FORCE -n "$IGNITE_NUM_CONTAINERS" "$IMAGE_NAME" || die "ducker-ignite up failed"
fi

DUCKTAPE_OPTIONS="--globals '$GLOBALS'"
# If parameters are passed in options than it must contain all possible parameters, otherwise None will be injected
if [[ "$PARAMETERS" != "{}" ]]; then
    DUCKTAPE_OPTIONS="$DUCKTAPE_OPTIONS --parameters '$PARAMETERS'"
fi

"$SCRIPT_DIR"/ducker-ignite test "$TC_PATHS" "$DUCKTAPE_OPTIONS" \
  || die "ducker-ignite test failed"