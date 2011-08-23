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
. ./environment-vars.sh

if [ -z ${MASTER} ]; then
    echo "\$MASTER not set!"
    exit 1
fi
if [ -z ${MASTER_ROOT} ]; then
    echo "\$MASTER_ROOT not set!"
    exit 1
fi
if [ -z ${SLAVE_ROOT} ]; then
    echo "\$SLAVE_ROOT not set!"
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

rm -rf ${SLAVE_ROOT}/install/${JOB_NAME}/${GIT_BRANCH}
mv ${WORKSPACE}/install ${SLAVE_ROOT}/install/${JOB_NAME}/${GIT_BRANCH}

LOCALHOST=`hostname -f`
if [[ ${MASTER} != "${LOCALHOST}" ]]; then
    rsync ${RSYNC_OPTS} ${SLAVE_ROOT}/install/${JOB_NAME}/${GIT_BRANCH}/ \
    ${MASTER}:${MASTER_ROOT}/install/${JOB_NAME}/${GIT_BRANCH}/
fi
