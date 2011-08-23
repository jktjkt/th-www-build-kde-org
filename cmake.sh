#!/bin/bash
. ${WORKSPACE}/environment-vars.sh

ARGS=""
ORIGARGS="$@"
while [ -n "$1" ]; do
    if [[ "$1" =~ "-G" ]]; then
	ARGS="${ARGS} $1 \""
	shift
	ARGS="${ARGS}$1"
	shift
        while [[ -n "$1" && "$1" =~ "^[:alpha:]" ]]; do
	    ARGS="${ARGS} $1"
            shift
        done
        ARGS="${ARGS}\""
    else
        ARGS="${ARGS} $1"
    fi
    shift
done

cmake ${ARGS}
