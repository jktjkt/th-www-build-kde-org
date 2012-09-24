#!/bin/bash -e

if [ -z ${JOB_TYPE} ]; then
	JOB_TYPE="build"
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

COMMON_DEPS="/srv/jenkins/install/deps"
JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"
if [[ -n ${BRANCH} ]]; then
	WANTED_BRANCH=${BRANCH}
else
	WANTED_BRANCH="${JOB_NAME##*_}"
fi
LOCALHOST=`hostname -f`

if [[ -f ${WORKSPACE}/build-kde-org.environment ]]; then
	echo -n "=> Loading build environment..."
	source ${WORKSPACE}/build-kde-org.environment
	echo " done"
fi

function FAIL {
	echo -e "\n=====================\n$@\n====================="
	# return if sourced and exit if executed
	[[ "$0" =~ "bash" ]] && return 1
	exit 1
}

function debug() {
	if [[ -n "${DEBUG}" ]]; then
		if [[ "${DEBUG}" =~ "${1}" ]] || [[ "${DEBUG}" == "*" ]]; then
			echo "DEBUG: $2"
		fi
	fi
}

function export_vars() {
	echo -e "=====================\n=> Exporting environment for later build steps\n====================="

	if [ -z "${DEPS}" ]; then
		echo "=>###############################"
		echo "=> WARN: No deps listed!"
		echo "=>###############################"
	fi

	export BUILD_DIR=$WORKSPACE/build
	unset CMAKE_PREFIX_PATH
	unset CMAKE_INSTALL_PREFIX
	unset QT_PLUGIN_PATH
	unset XDG_DATA_HOME
	unset XDG_DATA_DIRS
	unset XDG_CONFIG_HOME
	unset XDG_CONFIG_DIRS
	unset KDEDIRS

	local CLEAN_DEPS

	echo "=> Dependencies:"
	for DEP in ${DEPS}; do
		echo "=> Dep: ${DEP%=*}:${DEP#*=}"
	done

	pushd ${JENKINS_SLAVE_HOME}

	for DEP in ${DEPS}; do
		MODULE_PATH=${DEP%=*}
		MODULE_BRANCH=${DEP#*=}
		LIBPREFIX="64"

		if [ "$MODULE_PATH" == "Qt" ]; then
			MODULE_BRANCH=$QT_STABLE_BRANCH
			LIBPREFIX=""
		fi

		if [ "$MODULE_BRANCH" == "*" ] && [[ "${KDE_PROJECT}" == "false" ]]; then
			MODULE_BRANCH="master"
		elif [ "$MODULE_BRANCH" == "*" ]; then
			MODULE_BRANCH=$REAL_BRANCH
		fi

		MODULE=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve identifier ${MODULE_PATH}`

		if [ -z $MODULE ]; then
			MODULE=$MODULE_PATH
		fi

		MODULE_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${MODULE} ${MODULE_BRANCH}`
		if [ -z ${MODULE_BRANCH} ]; then
			MODULE_BRANCH=${REAL_BRANCH}
		fi

		CLEAN_DEPS="${CLEAN_DEPS} $MODULE_PATH=$MODULE_BRANCH"
		PREFIX="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}"

		echo "=> Adding $MODULE ($MODULE_PATH:$MODULE_BRANCH) to env vars..."
		CMAKE_PREFIX_PATH="${PREFIX}:${CMAKE_PREFIX_PATH}"
		PATH="${PREFIX}/bin:${PATH}"
		LD_LIBRARY_PATH="${PREFIX}/lib$LIBPREFIX:${LD_LIBRARY_PATH}"
		PKG_CONFIG_PATH="${PREFIX}/share/pkgconfig:${PREFIX}/lib$LIBPREFIX/pkgconfig:${PKG_CONFIG_PATH}"
		QT_PLUGIN_PATH="${PREFIX}/lib$LIBPREFIX/qt4/plugins:${PREFIX}/lib$LIBPREFIX/kde4/plugins:${QT_PLUGIN_PATH}"
		XDG_DATA_DIRS="${PREFIX}/share:${XDG_DATA_DIRS}"
		XDG_CONFIG_DIRS="${PREFIX}/etc/xdg:${XDG_CONFIG_DIRS}"
		KDEDIRS="${PREFIX}:${KDEDIRS}"

		QML_IMPORT_PATH="${PREFIX}/lib$LIBPREFIX/qt4/imports:${QML_IMPORT_PATH}"
		PYTHONPATH="${PREFIX}/lib64/python2.7/site-packages/:${PREFIX}/share/sip/:${PYTHONPATH}"
	done

	popd

	PREFIX="${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"

	export_var CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH%:}"

	export_var PATH "${JENKINS_SLAVE_HOME}:${PREFIX}/bin:${PATH%:}:${COMMON_DEPS}/bin"
	export_var LD_LIBRARY_PATH "${PREFIX}/lib64:${LD_LIBRARY_PATH%:}:${COMMON_DEPS}/lib64"
	export_var PKG_CONFIG_PATH "${PREFIX}/share/pkgconfig:${PREFIX}/lib64/pkgconfig:${PKG_CONFIG_PATH%:}:${COMMON_DEPS}/share/pkgconfig:${COMMON_DEPS}/lib64/pkgconfig"
	export_var QT_PLUGIN_PATH "${PREFIX}/lib64/qt4/plugins:${PREFIX}/lib64/kde4/plugins:${QT_PLUGIN_PATH%:}:${COMMON_DEPS}"
	export_var XDG_DATA_DIRS "${PREFIX}/share:${XDG_DATA_DIRS%:}:/usr/local/share/:/usr/share:${COMMON_DEPS}/share"
	export_var XDG_CONFIG_DIRS "${PREFIX}/etc/xdg:${XDG_CONFIG_DIRS%:}:/etc/xdg:${COMMON_DEPS}/etc/xdg"
	export_var KDEDIRS "${PREFIX}:${KDEDIRS%:}"
	export_var CMAKE_CMD_LINE "-DCMAKE_PREFIX_PATH=\"${CMAKE_PREFIX_PATH%:}\""

	export_var QML_IMPORT_PATH ${QML_IMPORT_PATH}
	export_var PYTHONPATH "${PYTHONPATH}:${COMMON_DEPS}/lib64/python2.7/site-packages:${COMMON_DEPS}/share/sip/"

	export_var KDE_PROJECT ${KDE_PROJECT}

	export_var DEPS "${CLEAN_DEPS}"
}

function export_var() {
	VAR=$1
	shift
	VALUE="$@"

	export $VAR="$VALUE"
	echo "export $VAR=\"$VALUE\"" >> ${WORKSPACE}/build-kde-org.environment

	echo "=> Exporting: $VAR=$VALUE"
}

function sync_from_master() {
	local BUILD_DEPS_AND_WAIT=$1
	echo -e "=====================\n=> Syncing dependencies from master\n====================="

	if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
		for DEP in ${DEPS}; do
			MODULE=${DEP%=*}
			MODULE_BRANCH=${DEP#*=}

			echo "Syncing $MODULE ($MODULE_BRANCH)..."
			if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
				mkdir -p ${ROOT}/install/${MODULE}/${MODULE_BRANCH}
				rsync ${RSYNC_OPTS} ${MASTER}:${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
				if [[ $? -ne 0 ]]; then
					echo -e "\n=====================\n=> Missing dependency: ${MODULE}:${MODULE_BRANCH}, scheduling a build"
					if [[ -n ${BUILD_DEPS_AND_WAIT} ]] && [[ "${BUILD_DEPS_AND_WAIT}" == "true" ]]; then
						schedule_build ${MODULE} ${MODULE_BRANCH}
					else
						FAIL "Missing dependency"
					fi
				fi
			fi
			echo "Syncing $MODULE ($MODULE_BRANCH)... done"
		done
	else
		echo "=> Running on master, skipping sync"
	fi
}

function sync_to_master() {
	echo -e "=====================\n=> Syncronizing build with master\n====================="

	if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
		if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
			ssh ${MASTER} mkdir -p "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"
			rsync ${RSYNC_OPTS} "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}/" "${MASTER}:${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}/"
		fi
	else
		echo "=> Running on master, skipping sync"
	fi
}

function save_results() {
	echo -e "=====================\n=> Saving build to install location\n====================="
	TRANSFER_OPTIONS=""

	if [[ "${PROJECT_PATH}" != "deps" ]]; then
		echo "=> Not a dependencies build - will clean install directory"
		TRANSFER_OPTIONS="--delete"
	fi

	basedir=`dirname "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"`
	echo -n "=> Syncing new install to global location (\"${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}\")..."
	if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
		mkdir -p "${basedir}"
		rsync -rlptgoD --checksum ${TRANSFER_OPTIONS} "${WORKSPACE}/install/${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}/" "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"
		rm -rf "${WORKSPACE}/install/${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"
	fi
	echo " done"
}

function schedule_build() {
	local MODULE
	local MODULE_BRANCH
	MODULE=$1
	MODULE_BRANCH=$2

	echo -e "=====================\n=> Scheduling a build of ${MODULE}_${MODULE_BRANCH}\n====================="

	pushd ${JENKINS_SLAVE_HOME}
	if [[ ! -f "jenkins-cli.jar" ]]; then
		wget http://sandbox.build.kde.org/jnlpJars/jenkins-cli.jar
	fi
	java -jar ./jenkins-cli.jar -i jenkins-private.key -s http://sandbox.build.kde.org build -s ${MODULE}_${MODULE_BRANCH} || FAIL "Dependency build failed"
	popd
}

function update_repo() {
	echo -e "\n=> update_repo\n"

	if [[ "$REPO_ADDRESS" =~ "git.kde.org" ]]; then
		update_git
	elif [[ "$REPO_ADDRESS" =~ "svn.kde.org" ]]; then
		update_svn
	#elif [[ "REPO_ADDRESS" =~ "bzr" ]]; then
	#	update_bzr
	else
		echo "=> Unknown repo type: $REPO_ADDRESS"
		FAIL
	fi
}

function update_git() {
	echo -e "\n=> update_git\n"

	if [ ! -d ".git" ]; then
		git clone $REPO_ADDRESS .
	fi

	(
		git fetch origin
		git checkout $REAL_BRANCH
		git merge --ff-only origin/$REAL_BRANCH
		git log -1 HEAD
	) || FAIL
}

function update_svn() {
	echo -e "\n=> update_svn\n"

	if [ ! -d ".svn" ]; then
		svn co $REPO_ADDRESS .
	fi

	(
		svn up
		svn log -1
	) || FAIL
}

function clean_workspace() {
	echo -e "=====================\n=> Cleaning workspace\n====================="
	pushd ${WORKSPACE}
	rm -f ${WORKSPACE}/build-kde-org.environment
	rm -rf ${WORKSPACE}/build
	if [[ -d ".git" ]]; then
		git clean -dfx
	fi
	popd
}