#!/bin/bash
# vim: set sw=4 sts=4 et tw=80 :
#===============================================================================
#
#          FILE:  make.sh
# 
#         USAGE:  As a make wrapper, to make sure that all needed environment
#                 variables are set. 
# 
#   DESCRIPTION:  Takes the given command line and tries to reapply quoting.
# 
#        AUTHOR:  Torgny Nyblom <nyblom@kde.org>
#       COMPANY:  KDE e.V.
#       VERSION:  1.0
#       CREATED:  08/23/2011 07:43:00 PM CEST
#===============================================================================

if [ -z "${WORKSPACE}" ]; then
    echo "\$WORKSPACE not set!"
fi

# TODO: Detect number of CPUs and use that as a limit to make ex: make -j $(($CPU_COUNT +1)) -l $(($CPU_COUNT))

CPU_COUNT=`grep -c processor /proc/cpuinfo`

DESTDIR=${WORKSPACE}/install INSTALL_ROOT=${WORKSPACE}/install make -l $CPU_COUNT -j $(($CPU_COUNT + 1)) "${@}"
