#!/bin/bash
# vim: set sw=4 sts=4 et tw=80 :
#===============================================================================
#
#          FILE:  post-build.sh
# 
#         USAGE:  As a post build task in Jenkins/Hudson, should only be run for
#                 successful builds. 
# 
#   DESCRIPTION:  Performs the following tasks:
#                 1: Remove the builds former global install directory
#                 2: Move the new builds install directory to the global place
#                 3: Sync the new builds global directory back to the master
# 
#        AUTHOR:  Torgny Nyblom <nyblom@kde.org>
#       COMPANY:  KDE e.V.
#       VERSION:  1.0
#       CREATED:  08/17/2011 08:19:54 PM CEST
#===============================================================================

RSYNC_OPTS="--recursive --links --perms --times --group --owner --devices \
--specials --delete-during --progress"

############################################
# Should not need to change anything below #
############################################

if [ -z ${MASTER} ]; then
    echo "\$MASTER not set!"
    exit 1
fi
if [ -z ${ROOT} ]; then
    echo "\$ROOT not set!"
    exit 1
fi
if [ -z ${JOB_NAME} ]; then
    echo "\$JOB_NAME not set!"
    exit 1
fi
if [ -z ${GIT_BRANCH} ]; then
    echo "\$GIR_BRANCH not set!"
    exit 1
fi
if [ -z ${WORKSPACE} ]; then
    echo "\$WORKSPACE not set!"
    exit 1
fi

rm -rf ${ROOT}/install/${JOB_NAME}/${GIT_BRANCH}
mv ${WORKSPACE}/install ${ROOT}/install/${JOB_NAME}/${GIT_BRANCH}
rsync ${RSYNC_OPTS} ${ROOT}/install/${JOB_NAME}/${GIT_BRANCH}/ \
    ${MASTER}:${ROOT}/install/${JOB_NAME}/${GIT_BRANCH}/