#!/bin/bash
# vim: set sw=4 sts=4 et tw=80 :
#===============================================================================
#
#          FILE:  cmake.sh
# 
#         USAGE:  As a cmake wrapper, to make sure that all needed environment
#                 variables are set. 
# 
#   DESCRIPTION:  Takes the given command line and tries to reapply quoting.
# 
#        AUTHOR:  Torgny Nyblom <nyblom@kde.org>
#       COMPANY:  KDE e.V.
#       VERSION:  1.0
#       CREATED:  08/23/2011 07:43:00 PM CEST
#===============================================================================
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
