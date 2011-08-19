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

. environment-vars.sh

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
unset XDG_DATA_HOME
unset XDG_DATA_DIRS
unset XDG_CONFIG_HOME
unset XDG_CONFIG_DIRS

for DEP in ${DEPS}; do
    MODULE=${DEP%=*}
    MODULE_BRANCH=${DEP#*=}

    echo "Syncing $MODULE ($MODULE_BRANCH) with ${MASTER}..."
    rsync ${RSYNC_OPTS} ${MASTER}:${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/

    echo "Adding $MODULE ($MODULE_BRANCH) to env vars..."
    echo "    CMAKE_PREFIX_PATH"
    echo export CMAKE_PREFIX_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_PREFIX_PATH}" >> environment-vars.sh
    echo "    CMAKE_INSTALL_PREFIX"
    export CMAKE_INSTALL_PREFIX="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_INSTALL_PREFIX}" >> environment-vars.sh
    echo "    PATH"
    export PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/bin:${PATH}" >> environment-vars.sh
    echo "    LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/lib:${LD_LIBRARY_PATH}" >> environment-vars.sh
    echo "    PKG_CONFIG_PATH"
    export PKG_CONFIG_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${PKG_CONFIG_PATH}" >> environment-vars.sh
    echo "    QT_PLUGIN_PATH"
    export QT_PLUGIN_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${QT_PLUGIN_PATH}" >> environment-vars.sh
    echo "    XDG_DATA_DIRS"
    export XDG_DATA_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/share:${XDG_DATA_DIRS}" >> environment-vars.sh
    echo "    XDG_CONFIG_DIRS"
    export XDG_CONFIG_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/etc/xdg:${XDG_CONFIG_DIRS}" >> environment-vars.sh
    echo "    KDEDIRS"
    export KDEDIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${KDEDIRS}" >> environment-vars.sh
done

