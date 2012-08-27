#!/bin/bash -e

echo -e "\n=====================\n=> Executing job...\n====================="

source ${JENKINS_SLAVE_HOME}/functions.sh

QT_CONFIG_OPTIONS="-fast -debug -separate-debug-info -system-zlib -system-libpng \
                   -system-libjpeg -dbus -webkit -plugin-sql-mysql -nomake examples \
                   -nomake demos -no-phonon -confirm-license -opensource"

case ${JOB_TYPE} in
	build)
		echo "=> Build mode"

		echo "=> Resolving project path..."
		pushd $JENKINS_SLAVE_HOME
		if [[ "${PROJECT}" == "Qt" ]]; then
			if [[ "$WANTED_BRANCH" == "stable" ]]; then
				REAL_BRANCH=${QT_STABLE_BRANCH}
			elif [[ "$WANTED_BRANCH" == "master" ]]; then
				REAL_BRANCH=${QT_FUTURE_BRANCH}
			elif [[ "${WANTED_BRANCH}" == "legacy" ]]; then
				REAL_BRANCH=${QT_LEGACY_BRANCH}
			else
				FAIL "Unknown Qt branch ${WANTED_BRANCH}"
			fi
		else
			REAL_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${WANTED_BRANCH}`
		fi
		if [[ "${PROJECT}" == "Qt" ]]; then
			PROJECT_PATH='Qt'
		elif [[ "${KDE_PROJECT}" == "true" ]]; then
			PROJECT_PATH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve path ${PROJECT}`
		else
			PROJECT_PATH=deps
		fi
		REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`
		popd
		echo "=> Resolving project path... ${PROJECT_PATH}"

		echo "=> Building ${PROJECT}:${REAL_BRANCH}"

		clean_workspace

		# Apply any local patches
		#echo "=> Apply local patches"
		#for f in ${ROOT}/patches/${JOB_NAME_DIR}/*.patch; do
		#	patch -p0 < ${f}
		#done

		echo -e "=====================\n=> Calculate dependencies\n====================="
		if [[ "${KDE_PROJECT}" == "true" ]]; then
			${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PROJECT_PATH} ${REAL_BRANCH}
		else
			${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PROJECT} ${REAL_BRANCH}
		fi
		source ${WORKSPACE}/build-kde-org.dependencies

		if [[ "${KDE_PROJECT}" == "false" ]]; then
			unset REAL_BRANCH
		fi
		export_vars
		sync_from_master #"true" #Try and build any missing dependencies

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
			INSTPREFIX="${ROOT}/install/${PROJECT_PATH}/${REAL_BRANCH}"
			if [[ "${PROJECT}" == "cmake" ]]; then
				${WORKSPACE}/bootstrap --prefix="${INSTPREFIX}"
			elif [[ "${PROJECT}" == "Qt" ]]; then
				cd ${WORKSPACE}
				./configure ${QT_CONFIG_OPTIONS} -prefix "${INSTPREFIX}"
			elif [[ "${PROJECT}" == "pyqt4" ]]; then
				cd ${WORKSPACE}
				python configure.py --confirm-license -u --bindir="${INSTPREFIX}/bin" --destdir="${INSTPREFIX}/lib64/python2.7/site-packages" --sipdir="${INSTPREFIX}/share/sip"
			else
				${JENKINS_SLAVE_HOME}/cmake.sh ${EXTRA_VARS} -DKDE4_BUILD_TESTS=ON -DLIB_SUFFIX=64 -DSIP_DEFAULT_SIP_DIR=${INSTPREFIX}/share/sip/ -DCMAKE_INSTALL_PREFIX=${INSTPREFIX} ..
			fi
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
echo -e "\n=====================\n=> Executing job... done\n====================="
