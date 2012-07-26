#!/bin/bash -ex

echo -e "\n=> execute-job.sh\n"

source functions.sh

rm -f environment-vars.sh

case ${JOB_TYPE} in
	build)
		pushd $JENKINS_SLAVE_HOME
		REAL_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${BRANCH}`
		PROJECT_PATH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve path ${PROJECT}`
		REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`
		popd

		#Wait for building direct dependencies here?
		#For unmet dep schedule a new build (Jenkins handles nested deps)
		#Reschedule this build again (will be built after the deps)

		echo "=> Building ${PROJECT}:${REAL_BRANCH}"

		git clean -dfx

		# Apply any local patches
		#for f in ${ROOT}/patches/${JOB_NAME_DIR}/*.patch; do
		#	patch -p0 < ${f}
		#done

		${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PROJECT_PATH} ${REAL_BRANCH}
		source environment-vars.sh
		export_vars
		sync_from_master

		rm -rf $WORKSPACE/build
		mkdir $WORKSPACE/build
		pushd $WORKSPACE/build

		local ENV=`env`
		debug "env" "Build env: ${ENV}"

		local EXTRA_VARS=""
		if [[ -n "${DEBUG}" ]] && [[ "${DEBUG}" =~ "make" ]]; then
			EXTRA_VARS="--debug-output"
		fi

		if [[ -z "${FAKE_EXECUTION}" ]] || [[ "${FAKE_EXECUTION}" == "false" ]]; then
			${JENKINS_SLAVE_HOME}/cmake.sh ${EXTRA_VARS} -DCMAKE_INSTALL_PREFIX=${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH} ..
			${JENKINS_SLAVE_HOME}/make.sh
			${JENKINS_SLAVE_HOME}/make.sh install
		fi

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