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

if [ -z "${CMAKE_CMD_LINE}" ]; then
    echo "CMAKE_CMD_LINE not set!"
fi

if [ -d /usr/lib/ccache ]; then
    export PATH=/usr/lib/ccache:${PATH}
fi

echo "=> cmake ${CMAKE_CMD_LINE} ${@}"
cmake ${CMAKE_CMD_LINE} "${@}"

