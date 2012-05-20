#!/bin/bash -ex

if [ -z ${JOB_TYPE} ]; then
	echo "=> JOB_TYPE not set!"
	FAIL
fi

if [ -z "${MASTER}" ]; then
    echo "MASTER not set!"
    FAIL
fi
if [ -z "${ROOT}" ]; then
    echo "ROOT not set!"
    FAIL
fi
if [ -z "${JOB_NAME}" ]; then
    echo "JOB_NAME not set!"
    FAIL
fi

if [ -z "${WORKSPACE}" ]; then
    echo "WORKSPACE not set!"
    FAIL
fi

RSYNC_OPTS="--recursive --links --perms --times --group --owner --devices \
            --specials --delete-during --update --checksum --human-readable --progress"

function FAIL {
	# return if sourced and exit if executed
	[ $0 ~= "bash" ] || return 1
	exit 1
}

function export_vars() {
	if [ -z "${DEPS}" ]; then
		echo "=>###############################"
		echo "=> WARN: No deps listed!"
		echo "=>###############################"
	fi

	unset CMAKE_PREFIX_PATH
	unset CMAKE_INSTALL_PREFIX
	unset QT_PLUGIN_PATH
	unset XDG_DATA_HOME
	#unset XDG_DATA_DIRS
	unset XDG_CONFIG_HOME
	#unset XDG_CONFIG_DIRS
	unset KDEDIRS

	for DEP in ${DEPS}; do
		MODULE=${DEP%=*}
		MODULE_BRANCH=${DEP#*=}

		echo "=> Adding $MODULE ($MODULE_BRANCH) to env vars..."
		CMAKE_PREFIX_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${CMAKE_PREFIX_PATH}"
		PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/bin:${PATH}"
		LD_LIBRARY_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/lib:${LD_LIBRARY_PATH}"
		PKG_CONFIG_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${PKG_CONFIG_PATH}"
		QT_PLUGIN_PATH="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${QT_PLUGIN_PATH}"
		XDG_DATA_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/share:${XDG_DATA_DIRS}"
		XDG_CONFIG_DIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}/etc/xdg:${XDG_CONFIG_DIRS}"
		KDEDIRS="${ROOT}/install/${MODULE}/${MODULE_BRANCH}:${KDEDIRS}"
	done

	export CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH%:}"
	export PATH="${JENKINS_SLAVE_HOME}:${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${PATH%:}"
	export LD_LIBRARY_PATH="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}/lib:${LD_LIBRARY_PATH%:}"
	export PKG_CONFIG_PATH="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${PKG_CONFIG_PATH%:}"
	export QT_PLUGIN_PATH="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${QT_PLUGIN_PATH%:}"
	export XDG_DATA_DIRS="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}/share:${XDG_DATA_DIRS%:}:/usr/local/share/:/usr/share"
	export XDG_CONFIG_DIRS="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}/etc/xdg:${XDG_CONFIG_DIRS%:}:/etc/xdg"
	export KDEDIRS="${ROOT}/install/${JOB_NAME_DIR}/${BRANCH}:${KDEDIRS%:}"
	export CMAKE_CMD_LINE="-DCMAKE_PREFIX_PATH=\"${CMAKE_PREFIX_PATH%:}\""
}

function sync_from_master() {
	if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
		echo "=> Syncing..."
		for DEP in ${DEPS}; do
			MODULE=${DEP%=*}
			MODULE_BRANCH=${DEP#*=}

			#lock_dir ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
			echo "Syncing $MODULE ($MODULE_BRANCH) with ${MASTER}..."
			mkdir -p ${ROOT}/install/${MODULE}/${MODULE_BRANCH}
			rsync ${RSYNC_OPTS} ${MASTER}:${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
			#unlock_dir ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
		done
	else
		echo "=> Running on master, skipping sync"
	fi
}

function sync_to_master() {
	if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
		echo "=> Syncing changes with master (\"${MASTER}\")..."
		rsync ${RSYNC_OPTS} "${ROOT}/install/${PROJECT}/${BRANCH}/" "${MASTER}:${ROOT}/install/${PROJECT}/${BRANCH}/"
		echo "=> done"
	else
		echo "=> Running on master, skipping sync"
	fi
}

function save_results() {
	echo -n "=> Removing old install dir (\"${ROOT}/install/${PROJECT}/${BRANCH}\")..."
	rm -rf "${ROOT}/install/${PROJECT}/${BRANCH}"
	echo " done"
	basedir=`dirname "${ROOT}/install/${PROJECT}/${BRANCH}"`
	echo -n "=> Moving new install to global location (\"${ROOT}/install/${PROJECT}/${BRANCH}\")..."
	mkdir -p "${basedir}"
	mv "${WORKSPACE}/install/${ROOT}/install/${PROJECT}/${BRANCH}" "${ROOT}/install/${PROJECT}/${BRANCH}"
	echo " done"
}

function set_revision {
	#if [ -d .git ]; then
	#	git checkout ${REVISION}
	#elif [ -d .svn ]; then
	#	svn co ${REPO_URL}
	#fi
}

JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"
BRANCH="${JOB_NAME#*_}"
LOCALHOST=`hostname -f`

echo "=> Building ${PROJECT}:${BRANCH}"

rm -r environment-vars.sh

case ${JOB_TYPE} in
	build)
		BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve ${PROJECT} ${BRANCH}`
		${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PROJECT} ${BRANCH}
		source environment-vars.sh
		sync_from_master
		export_vars
		${JENKINS_SLAVE_HOME}/cmake.sh
		${JENKINS_SLAVE_HOME}/make.sh
		save_results
		sync_to_master
		${JENKINS_SLAVE_HOME}/ctest.sh
		;;
	package)
		set_revision
		;;
esac

# Apply any local patches
#for f in /srv/patches/${JOB_NAME_DIR}/*.patch; do
#	patch -p0 < ${f}
#done
