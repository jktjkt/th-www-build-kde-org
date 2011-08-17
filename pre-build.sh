#!/bin/bash
# vim: set sw=4 sts=4 et tw=80 :
#===============================================================================
#
#          FILE:  pre-build.sh
# 
#         USAGE:  As the first build step in Jenkins/Hudson 
# 
#   DESCRIPTION:  This script shall perform the following task:
#                 1: Sync changes from other nodes to this node for the needed
#                 dependencies
#                 2: Add the required directories for each dependency to all
#                 needed environment variables
# 
#        AUTHOR:  Torgny Nyblom <nyblom@kde.org>
#       COMPANY:  KDE e.V.
#       VERSION:  1.0
#       CREATED:  08/17/2011 08:19:54 PM CEST
#===============================================================================
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
    echo "\$GIT_BRANCH not set!"
    exit 1
fi
if [ -z ${WORKSPACE} ]; then
    echo "\$WORKSPACE not set!"
    exit 1
fi
if [ -z ${DEPS} ]; then
    echo "###############################"
    echo " WARN: No deps listed!"
    echo "###############################"
fi
####################
# Update as needed #
####################
#DEPS="kdelibs=KDE/4.7 \
#    kdepimlibs=master"

RSYNC_OPTS="--recursive --links --perms --times --group --owner --devices \
            --specials --delete-during --progress"
############################################
# Should not need to change anything below #
############################################


unset CMAKE_PREFIX_PATH
unset CMAKE_INSTALL_PREFIX
unset QT_PLUGIN_PATH
unset XGD_DATA_HOME
unset XGD_DATA_DIRS
unset XGD_CONFIG_HOME
unset XGD_CONFIG_DIRS

#export XGD_DATA_HOME="${ROOT}/install/${GIT_BRANCH}"
#export XGD_CONFIG_HOME="${ROOT}/install/${GIT_BRANCH}"

for DEP in ${DEPS}; do
    MODULE=${DEP%=*}
    MODULE_BRANCH=${DEP#*=}

    echo "Syncing $MODULE ($MODULE_BRANCH) with ${MASTER}..."
    rsync ${RSYNC_OPTS} ${MASTER}:${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ ${ROOT}/install/${JOB_NAME}/${GIT_BRANCH}/

    echo "Adding $MODULE ($MODULE_BRANCH) to env vars..."
    echo "    CMAKE_PREFIX_PATH"
    export CMAKE_PREFIX_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_PREFIX_PATH}"
    echo "    CMAKE_INSTALL_PREFIX"
    export CMAKE_INSTALL_PREFIX="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_INSTALL_PREFIX}"
    echo "    PATH"
    export PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/bin:${PATH}"
    echo "    LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/lib:${LD_LIBRARY_PATH}"
    echo "    PKG_CONFIG_PATH"
    export PKG_CONFIG_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${PKG_CONFIG_PATH}"
    echo "    QT_PLUGIN_PATH"
    export QT_PLUGIN_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${QT_PLUGIN_PATH}"
    echo "    XGD_DATA_DIRS"
    export XGD_DATA_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/share:${XGD_DATA_DIRS}"
    echo "    XGD_CONFIG_DIRS"
    export XGD_CONFIG_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/etc/xgd:${XGD_CONFIG_DIRS}"
done

