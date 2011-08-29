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
if [ -z ${SLAVE_ROOT} ]; then
    echo "\$SLAVE_ROOT not set!"
    exit 1
fi
if [ -z ${MASTER_ROOT} ]; then
    echo "\$MASTER_ROOT not set!"
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
if [ -z "${DEPS}" ]; then
    echo "###############################"
    echo " WARN: No deps listed!"
    echo "###############################"
fi

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

LOCALHOST=`hostname -f`
for DEP in ${DEPS}; do
    MODULE=${DEP%=*}
    MODULE_BRANCH=${DEP#*=}
    MODULE_BRANCH_DIR=${MODULE_BRANCH/\/_/}

    if [[ ${MASTER} != "${LOCALHOST}" ]]; then
        echo "Syncing $MODULE ($MODULE_BRANCH) with ${MASTER}..."
	mkdir -p ${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}
        rsync ${RSYNC_OPTS} ${MASTER}:${MASTER_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}/ ${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}/
    fi

    echo "Adding $MODULE ($MODULE_BRANCH) to env vars..."
    CMAKE_PREFIX_PATH="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}:${CMAKE_PREFIX_PATH}"
    #CMAKE_INSTALL_PREFIX="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_INSTALL_PREFIX}"
    PATH="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH}/bin:${PATH}"
    LD_LIBRARY_PATH="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}/lib:${LD_LIBRARY_PATH}"
    PKG_CONFIG_PATH="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}:${PKG_CONFIG_PATH}"
    QT_PLUGIN_PATH="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}:${QT_PLUGIN_PATH}"
    XDG_DATA_DIRS="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}/share:${XDG_DATA_DIRS}"
    XDG_CONFIG_DIRS="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}/etc/xdg:${XDG_CONFIG_DIRS}"
    KDEDIRS="${SLAVE_ROOT}/install/${MODULE}/${MODULE_BRANCH_DIR}:${KDEDIRS}"
done

echo export CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}" >> environment-vars.sh
#echo export CMAKE_INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX}" >> environment-vars.sh
echo export PATH="${JENKINS_SLAVE_HOME}:${PATH}" >> environment-vars.sh
echo export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" >> environment-vars.sh
echo export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}" >> environment-vars.sh
echo export QT_PLUGIN_PATH="${QT_PLUGIN_PATH}" >> environment-vars.sh
echo export XDG_DATA_DIRS="${XDG_DATA_DIRS}" >> environment-vars.sh
echo export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS}" >> environment-vars.sh
echo export KDEDIRS="${KDEDIRS}" >> environment-vars.sh
