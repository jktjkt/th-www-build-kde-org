#!/bin/bash -x
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

source environment-vars.sh

if [ -z "${MASTER}" ]; then
    echo "\$MASTER not set!"
    exit 1
fi
if [ -z "${ROOT}" ]; then
    echo "\$ROOT not set!"
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
if [ -z "${DEPS}" ]; then
    echo "###############################"
    echo " WARN: No deps listed!"
    echo "###############################"
fi

RSYNC_OPTS="--recursive --links --perms --times --group --owner --devices \
            --specials --delete-during --update --checksum --human-readable --progress"

############################################
# Should not need to change anything below #
############################################

unset CMAKE_PREFIX_PATH
unset CMAKE_INSTALL_PREFIX
unset QT_PLUGIN_PATH
unset XDG_DATA_HOME
#unset XDG_DATA_DIRS
unset XDG_CONFIG_HOME
#unset XDG_CONFIG_DIRS
unset KDEDIRS

BRANCH=${GIT_BRANCH/refs\//}
BRANCH=${BRANCH/heads\//}
BRANCH=${BRANCH/origin\//}
BRANCH=${BRANCH/remotes\//}
JOB_NAME_DIR=${JOB_NAME%_*}

LOCALHOST=`hostname -f`
for DEP in ${DEPS}; do
    MODULE=${DEP%=*}
    MODULE_BRANCH=${DEP#*=}

    if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
        echo "Syncing $MODULE ($MODULE_BRANCH) with ${MASTER}..."
	mkdir -p ${ROOT}/install/${MODULE}/${MODULE_BRANCH}
        rsync ${RSYNC_OPTS} ${MASTER}:${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
    fi

    echo "Adding $MODULE ($MODULE_BRANCH) to env vars..."
    CMAKE_PREFIX_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_PREFIX_PATH}"
    PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/bin:${PATH}"
    LD_LIBRARY_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/lib:${LD_LIBRARY_PATH}"
    PKG_CONFIG_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${PKG_CONFIG_PATH}"
    QT_PLUGIN_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${QT_PLUGIN_PATH}"
    XDG_DATA_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/share:${XDG_DATA_DIRS}"
    XDG_CONFIG_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/etc/xdg:${XDG_CONFIG_DIRS}"
    KDEDIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${KDEDIRS}"
done

echo export CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH%:}" >> environment-vars.sh
echo export PATH="${JENKINS_SLAVE_HOME}:${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${PATH%:}" >> environment-vars.sh
echo export LD_LIBRARY_PATH="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}/lib:${LD_LIBRARY_PATH%:}" >> environment-vars.sh
echo export PKG_CONFIG_PATH="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${PKG_CONFIG_PATH%:}" >> environment-vars.sh
echo export QT_PLUGIN_PATH="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${QT_PLUGIN_PATH%:}" >> environment-vars.sh
echo export XDG_DATA_DIRS="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}/share:${XDG_DATA_DIRS%:}:/usr/local/share/:/usr/share" >> environment-vars.sh
echo export XDG_CONFIG_DIRS="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}/etc/xdg:${XDG_CONFIG_DIRS%:}:/etc/xdg" >> environment-vars.sh
echo export KDEDIRS="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${KDEDIRS%:}" >> environment-vars.sh
echo CMAKE_CMD_LINE="-DCMAKE_PREFIX_PATH=\"${CMAKE_PREFIX_PATH%:}\"" >> environment-vars.sh


# Apply any local patches
#for f in /srv/patches/${JOB_NAME_DIR}/*.patch; do
#	patch -p0 < ${f}
#done
