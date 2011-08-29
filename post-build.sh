#!/bin/bash -x
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

LOCALHOST=`hostname -f`

if [ -z "${MASTER}" ]; then
    echo "\$MASTER not set!"
    exit 1
fi
if [ -z "${MASTER_ROOT}" ]; then
    echo "\$MASTER_ROOT not set!"
    exit 1
fi
if [[ "${MASTER}" == "${LOCALHOST}" ]]; then
	SLAVE_ROOT="${MASTER_ROOT}"
fi

if [ -z "${SLAVE_ROOT}" ]; then
    echo "\$SLAVE_ROOT not set!"
    exit 1
fi
if [ -z "${JOB_NAME}" ]; then
    echo "\$JOB_NAME not set!"
    exit 1
fi
if [ -z "${GIT_BRANCH}" ]; then
    echo "\$GIT_BRANCH not set!"
    exit 1
fi
if [ -z "${WORKSPACE}" ]; then
    echo "\$WORKSPACE not set!"
    exit 1
fi

GIT_BRANCH_DIR=${GIT_BRANCH/\//_/}
JOB_NAME_DIR=${JOB_NAME%_*}
echo -n "=> Removing old install dir..."
rm -rf "${SLAVE_ROOT}/install/${JOB_NAME_DIR}/${GIT_BRANCH_DIR}"
echo " done"
basedir=`dirname "${SLAVE_ROOT}/install/${JOB_NAME_DIR}/${GIT_BRANCH_DIR}"`
echo -n "=> Moving new install to global location..."
mkdir -p "${basedir}"
mv "${WORKSPACE}/install" "${SLAVE_ROOT}/install/${JOB_NAME_DIR}/${GIT_BRANCH_DIR}"
echo " done"

if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
    echo "=> Syncing changes with master..."
    rsync "${RSYNC_OPTS} ${SLAVE_ROOT}/install/${JOB_NAME_DIR}/${GIT_BRANCH_DIR}/" \
    "${MASTER}:${MASTER_ROOT}/install/${JOB_NAME_DIR}/${GIT_BRANCH_DIR}/"
    echo "=> done"
fi
