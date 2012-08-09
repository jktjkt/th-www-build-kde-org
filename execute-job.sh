#!/bin/bash -e

echo -e "\n=> execute-job.sh\n"

source ${JENKINS_SLAVE_HOME}/functions.sh

case ${JOB_TYPE} in
	build)
		echo -e "\n=> Build mode\n"

		pushd $JENKINS_SLAVE_HOME
		REAL_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${BRANCH}`
		if [[ "${KDE_PROJECT}" == "true" ]]; then
			PROJECT_PATH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve path ${PROJECT}`
		else
			PROJECT_PATH=deps
		fi
		REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`
		popd

		#Wait for building direct dependencies here?
		#For unmet dep schedule a new build (Jenkins handles nested deps)
		#Reschedule this build again (will be built after the deps)

		echo "=> Building ${PROJECT}:${REAL_BRANCH}"

		clean_workspace

		# Apply any local patches
		#echo "=> Apply local patches"
		#for f in ${ROOT}/patches/${JOB_NAME_DIR}/*.patch; do
		#	patch -p0 < ${f}
		#done

		echo "=> Calculate dependencies"
		${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PROJECT_PATH} ${REAL_BRANCH}
		source ${WORKSPACE}/build-kde-org.dependencies

		if [[ "${KDE_PROJECT}" == "false" ]]; then
			unset REAL_BRANCH
		fi
		export_vars
		sync_from_master

		mkdir $WORKSPACE/build
		pushd $WORKSPACE/build

		ENV=`env`
		debug "env" "Build env: ${ENV}"

		EXTRA_VARS=""
		if [[ -n "${DEBUG}" ]] && [[ "${DEBUG}" =~ "make" ]]; then
			EXTRA_VARS="--debug-output"
		fi

		echo "=> Building..."
		if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
			${JENKINS_SLAVE_HOME}/cmake.sh ${EXTRA_VARS} -DCMAKE_INSTALL_PREFIX=${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH} ..
			${JENKINS_SLAVE_HOME}/make.sh
			${JENKINS_SLAVE_HOME}/make.sh install
		fi

		echo "=> Building done"

		save_results
		sync_to_master

		if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
			${JENKINS_SLAVE_HOME}/ctest.sh
			if [[ ! -f $WORKSPACE/build/cppcheck.xml ]]; then
				debug "test" "No cppcheck result found, faking an empty one"
				echo -e '<?xml version="1.0" encoding="UTF-8"?>\n<results>\n</results>' > $WORKSPACE/build/cppcheck.xml
			fi
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