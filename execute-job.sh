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

COMMON_DEPS="/srv/jenkins/install/deps"
JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"
BRANCH="${JOB_NAME##*_}"
LOCALHOST=`hostname -f`


function FAIL {
	echo $@
	# return if sourced and exit if executed
	[[ "$0" =~ "bash" ]] && return 1
	exit 1
}

function export_vars() {
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
	#unset XDG_DATA_DIRS
	unset XDG_CONFIG_HOME
	#unset XDG_CONFIG_DIRS
	unset KDEDIRS

	local CLEAN_DEPS

	for DEP in ${DEPS}; do
		MODULE_PATH=${DEP%=*}
		MODULE_BRANCH=${DEP#*=}

		if [ "$MODULE_PATH" == "Qt" ]; then
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
	export PATH="${JENKINS_SLAVE_HOME}:${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${PATH%:}:${COMMON_DEPS}/bin"
	export LD_LIBRARY_PATH="${ROOT}/install/${PROJECT}/${REAL_BRANCH}/lib:${LD_LIBRARY_PATH%:}:${COMMON_DEPS}/lib"
	export PKG_CONFIG_PATH="${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${PKG_CONFIG_PATH%:}:${COMMON_DEPS}"
	export QT_PLUGIN_PATH="${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${QT_PLUGIN_PATH%:}:${COMMON_DEPS}"
	export XDG_DATA_DIRS="${ROOT}/install/${PROJECT}/${REAL_BRANCH}/share:${XDG_DATA_DIRS%:}:/usr/local/share/:/usr/share:${COMMON_DEPS}/share"
	export XDG_CONFIG_DIRS="${ROOT}/install/${PROJECT}/${REAL_BRANCH}/etc/xdg:${XDG_CONFIG_DIRS%:}:/etc/xdg:${COMMON_DEPS}/etc/xdg"
	export KDEDIRS="${ROOT}/install/${PROJECT}/${REAL_BRANCH}:${KDEDIRS%:}"
	export CMAKE_CMD_LINE="-DCMAKE_PREFIX_PATH=\"${CMAKE_PREFIX_PATH%:}\""

	DEPS=$CLEAN_DEPS
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
			rsync ${RSYNC_OPTS} ${MASTER}:${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/ || FAIL "Required dependency: $MODULE/$MODULE_BRANCH was not found on master"
			#unlock_dir ${ROOT}/install/${MODULE}/${MODULE_BRANCH}/
		done
	else
		echo "=> Running on master, skipping sync"
	fi
}

function sync_to_master() {
	if [[ "${MASTER}" != "${LOCALHOST}" ]]; then
		echo "=> Syncing changes with master (\"${MASTER}\")..."
		ssh ${MASTER} mkdir -p "${ROOT}/install/${PROJECT}/${BRANCH}"
		rsync ${RSYNC_OPTS} "${ROOT}/install/${PROJECT}/${REAL_BRANCH}/" "${MASTER}:${ROOT}/install/${PROJECT}/${BRANCH}/"
		echo "=> done"
	else
		echo "=> Running on master, skipping sync"
	fi
}

function save_results() {
	echo -n "=> Removing old install dir (\"${ROOT}/install/${PROJECT}/${REAL_BRANCH}\")..."
	rm -rf "${ROOT}/install/${PROJECT}/${REAL_BRANCH}"
	echo " done"
	basedir=`dirname "${ROOT}/install/${PROJECT}/${REAL_BRANCH}"`
	echo -n "=> Moving new install to global location (\"${ROOT}/install/${PROJECT}/${REAL_BRANCH}\")..."
	mkdir -p "${basedir}"
	mv "${WORKSPACE}/install/${ROOT}/install/${PROJECT}/${REAL_BRANCH}" "${ROOT}/install/${PROJECT}/${BRANCH}"
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

function update_repo() {

	if [[ "$REPO_ADDRESS" =~ "git.kde.org" ]]; then
		echo "Sleeping for $POLL_DELAY seconds to allow mirrors to sync"
		sleep $POLL_DELAY
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
	if [ ! -d ".svn" ]; then
		svn co $REPO_ADDRESS .
	fi

	(
		svn up
		svn log -1
	) || FAIL
}

function main() {
	rm -f environment-vars.sh

	case ${JOB_TYPE} in
		build)
			pushd $JENKINS_SLAVE_HOME
			REAL_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${BRANCH}`
			PROJECT_PATH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve path ${PROJECT}`
			REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`
			popd

			#Wait for building direct dependencies here?

			echo "=> Building ${PROJECT}:${REAL_BRANCH}"

			#update_repo

			${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PROJECT_PATH} ${REAL_BRANCH}
			source environment-vars.sh
			export_vars
			sync_from_master

			rm -rf $WORKSPACE/build
			git clean -dnx
			mkdir $WORKSPACE/build
			pushd $WORKSPACE/build
			${JENKINS_SLAVE_HOME}/cmake.sh -DCMAKE_INSTALL_PREFIX=${ROOT}/install/${PROJECT}/${REAL_BRANCH} ..
			${JENKINS_SLAVE_HOME}/make.sh
			${JENKINS_SLAVE_HOME}/make.sh install
			save_results
			sync_to_master
			${JENKINS_SLAVE_HOME}/ctest.sh
			if [[ ! -f $WORKSPACE/build/cppcheck.xml ]]; then
				echo -e '<?xml version="1.0" encoding="UTF-8"?>\n<results>\n</results>' > $WORKSPACE/build/cppcheck.xml
			fi
			popd
			;;
		package)
			# 1: Package
			# 2: Build and test the new package against the latest packaged dependencies.
			#    Trigger a build with special options, real_branch set to version?
			#    Do it here inline?
			#    Do all packaging first then build all packages or one by one?
			;;
	esac

	# Apply any local patches
	#for f in /srv/patches/${JOB_NAME_DIR}/*.patch; do
	#	patch -p0 < ${f}
	#done
}

if [[ "$0" =~ "bash" ]]; then
	main
fi
