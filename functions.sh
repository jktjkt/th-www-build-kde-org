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

	for DEP in ${DEPS}; do
		MODULE_PATH=${DEP%=*}
		MODULE_BRANCH=${DEP#*=}

		if [ "$MODULE_PATH" == "qt" ]; then
			MODULE_BRANCH=$QT_STABLE_BRANCH
		fi

		if [ "$MODULE_BRANCH" == "*" ]; then
			MODULE_BRANCH=$REAL_BRANCH
		fi

		pushd ${JENKINS_SLAVE_HOME}
		MODULE=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve identifier ${MODULE_PATH}`
		popd

		if [ -z $MODULE ]; then
			MODULE=$MODULE_PATH
		fi

		CLEAN_DEPS="${CLEAN_DEPS} $MODULE_PATH=$MODULE_BRANCH"

		echo "=> Adding $MODULE ($MODULE_PATH:$MODULE_BRANCH) to env vars..."
		CMAKE_PREFIX_PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}:${CMAKE_PREFIX_PATH}"
		PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}/bin:${PATH}"
		LD_LIBRARY_PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}/lib:${LD_LIBRARY_PATH}"
		PKG_CONFIG_PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}:${PKG_CONFIG_PATH}"
		QT_PLUGIN_PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}:${QT_PLUGIN_PATH}"
		XDG_DATA_DIRS="${ROOT}/install/${MODULE_PAHT}/${MODULE_BRANCH}/share:${XDG_DATA_DIRS}"
		XDG_CONFIG_DIRS="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}/etc/xdg:${XDG_CONFIG_DIRS}"
		KDEDIRS="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}:${KDEDIRS}"

		QML_IMPORT_PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}/lib/qt4/imports:${QML_IMPORT_PATH}"
		QMAKEPATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}/share/qt4/mkspecs/modules:${QMAKEPATH}"
		QT_PLUGIN_PATH="${ROOT}/install/${MODULE_PATH}/${MODULE_BRANCH}/lib/qt4/plugins/designer:${QT_PLUGIN_PATH}"
	done

	export_var CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH%:}"

	if [[ -d "/usr/lib/ccache/" ]]; then
		PATH="/usr/lib/ccache/:${PATH}"
		ccache -M 10G
	fi
	export_var PATH "${JENKINS_SLAVE_HOME}:${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${PATH%:}:${COMMON_DEPS}/bin"

	export_var LD_LIBRARY_PATH "${ROOT}/install/${PROJECT}/${REAL_BRANCH}/lib:${LD_LIBRARY_PATH%:}:${COMMON_DEPS}/lib"
	export_var PKG_CONFIG_PATH "${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${PKG_CONFIG_PATH%:}:${COMMON_DEPS}"
	export_var QT_PLUGIN_PATH "${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${QT_PLUGIN_PATH%:}:${COMMON_DEPS}"
	export_var XDG_DATA_DIRS "${ROOT}/install/${PROJECT}/${REAL_BRANCH}/share:${XDG_DATA_DIRS%:}:/usr/local/share/:/usr/share:${COMMON_DEPS}/share"
	export_var XDG_CONFIG_DIRS "${ROOT}/install/${PROJECT}/${REAL_BRANCH}/etc/xdg:${XDG_CONFIG_DIRS%:}:/etc/xdg:${COMMON_DEPS}/etc/xdg"
	export_var KDEDIRS "${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${KDEDIRS%:}"
	export_var CMAKE_CMD_LINE "-DCMAKE_PREFIX_PATH=\"${CMAKE_PREFIX_PATH%:}\""

	export_var QML_IMPORT_PATH ${QML_IMPORT_PATH}
	export_var QMAKEPATH ${QMAKEPATH}
	export_var QT_PLUGIN_PATH ${QT_PLUGIN_PATH}

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

			#lock_dir ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
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
			#unlock_dir ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
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

	if [[ "${PROJECT_PATH}" != "deps" ]]; then
		echo -n "=> Removing old install dir (\"${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}\")..."
		if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
			rm -rf "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"
		fi
		echo " done"
	else
		echo "=> Dependency build, will not remove old install dir"
	fi

	basedir=`dirname "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"`
	echo -n "=> Moving new install to global location (\"${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}\")..."
	if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
		mkdir -p "${basedir}"
		mv "${WORKSPACE}/install/${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}" "${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"
	fi
	echo " done"
}

function set_revision() {
	echo "No not yet"
	#if [ -d .git ]; then
	#	git checkout ${REVISION}
	#elif [ -d .svn ]; then
	#	svn co ${REPO_URL}
	#fi
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