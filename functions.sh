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
NUM_PROC=$(($(grep -c processor /proc/cpuinfo)+1))
JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"
if [[ -n ${BRANCH} ]]; then
	WANTED_BRANCH=${BRANCH}
else
	WANTED_BRANCH="${JOB_NAME##*_}"
fi
LOCALHOST=`hostname -f`

if [[ -n ${KDE_VERSION} ]]; then
	FULL_VERSION=${KDE_VERSION}
	MAJOR_MINOR_VERSION=${FULL_VERSION%.*}
	MAJOR_VERSION=${FULL_VERSION%%.*}
	MINOR_VERSION=${MAJOR_MINOR_VERSION##*.}
	PATCH_VERSION=${FULL_VERSION##*.}
fi

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
		wget http://${MASTER}:${HTTP_PORT:-80}/jnlpJars/jenkins-cli.jar
	fi
	java -jar ./jenkins-cli.jar -i jenkins-private.key -s http://${MASTER}:${HTTP_PORT:-80} build -s ${MODULE}_${MODULE_BRANCH} || FAIL "Dependency build failed"
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

function create_checksums {
	echo "=> Saving checksums of generated tarball(s)..."
	pushd ${WORKSPACE}/sources
	sha256sum *.tar* > sha256sums.txt
	sha1sum *.tar* > sha1sums.txt
	if [[ -d kde-l10n ]]; then
		pushd kde-l10n
		sha256sum *.tar* >> ../sha256sums.txt
		sha1sum *.tar* >> ../sha1sums.txt
		popd
	fi
	popd
	echo "=> Saving checksums of generated tarball(s)... done"
}

function record_versions {
	echo "=> Saving revisions/hashes used to generate tarball(s)..."
	pushd ${WORKSPACE}/clean
	rm -rf ${WORKSPACE}/sources/versions.txt
	for d in *; do
		pushd ${d}
		local VERSION
		if [[ -d .git ]]; then
			VERSION=`git rev-parse HEAD`
		elif [[ -d .svn ]]; then
			VERSION=`svn info | sed -n -e '/^Revision: \([0-9]*\).*$/s//\1/p'`
		fi
		echo "${d} ${VERSION}" >> ${WORKSPACE}/sources/versions.txt
		popd
	done
	popd
	echo "=> Saving revisions/hashes used to generate tarball(s)... done"
}

function setup_packaging() {
	echo -e "=====================\n=> Installing/Updating packaging tools\n====================="
	mkdir -p ${JENKINS_SLAVE_HOME}/packaging
	pushd ${JENKINS_SLAVE_HOME}/packaging
	if [[ ! -d .svn ]]; then
		svn co ${SVN_URL} .
	else
		svn up
	fi
	popd
}

function create_packaging_helpers() {
	echo -e "=====================\n=> Creating/updating documentation tools\n====================="
	if [[ "${JOB_NAME}" -eq "package-kde-sc" ]]; then
		pushd ${WORKSPACE}
		mkdir -p borrame
		cp -R clean/kdelibs/kdoctools/* borrame/

		if [[ ! -x docbookl10nhelper ]]; then
			echo "=> Generate docbookl10nhelper..."
			pushd borrame
			g++ -lQtCore -L${ROOT}/install/Qt/${QT_STABLE_BRANCH}/lib -I${ROOT}/install/Qt/${QT_STABLE_BRANCH}/include -I${ROOT}/install/Qt/${QT_STABLE_BRANCH}/include/Qt -I${ROOT}/install/Qt/${QT_STABLE_BRANCH}/include/QtCore docbookl10nhelper.cpp -o ../docbookl10nhelper
			popd
			echo "=> Generate docbookl10nhelper... done"
		fi

		if [[ ! -f borrame/customization/dtd/kdex.dtd ]]; then
			echo "=> Generate xml templates..."
			DOCBOOK_LOCATION=/usr/share/xml/docbook/schema/dtd/4.2/
			DOCBOOKXSL_LOCATION=/usr/share/xml/docbook/stylesheet/nwalsh/
			sed s#@DOCBOOKXML_CURRENTDTD_DIR@#$DOCBOOK_LOCATION#g borrame/customization/dtd/kdex.dtd.cmake > borrame/customization/dtd/kdex.dtd
			sed s#@DOCBOOKXSL_DIR@#$DOCBOOKXSL_LOCATION#g borrame/customization/kde-include-common.xsl.cmake > borrame/customization/kde-include-common.xsl
			sed s#@DOCBOOKXSL_DIR@#$DOCBOOKXSL_LOCATION#g borrame/customization/kde-include-man.xsl.cmake > borrame/customization/kde-include-man.xsl
			./docbookl10nhelper $DOCBOOKXSL_LOCATION borrame/customization/xsl/ borrame/customization/xsl/
			echo "=> Generate xml templates... done"
		fi

		rsync -rlptgoD --checksum --delete "borrame" "${JENKINS_SLAVE_HOME}/packaging/"
		popd
	elif [[ ! -d ${JENKINS_SLAVE_HOME}/packaging/borrame ]]; then
		echo "=> l10n helpers not present, documentation/translations generation will not be successful"
	fi
}

function package() {
	echo -e "=====================\n=> Packaging ${PROJECT}\n====================="
	echo "=> Removing SCM info..."
	${JENKINS_SLAVE_HOME}/packaging/anon ${PROJECT}
	echo "=> Removing SCM info... done"
	echo "=> Preparing for distribution..."
	${JENKINS_SLAVE_HOME}/packaging/dist ${PROJECT}
	echo "=> Preparing for distribution... done"
	echo "=> Making package..."
	${JENKINS_SLAVE_HOME}/packaging/taritup ${PROJECT} ${KDE_VERSION}
	echo "=> Making package... done"
}

function make_docs() {
	echo "=> Make docs..."
	pushd ${PROJECT}
	make -k -f ${JENKINS_SLAVE_HOME}/packaging/Makefile.docu -j$NUM_PROC SOURCE_DIR=${WORKSPACE}/sources KDOCTOOLS_DIR=${JENKINS_SLAVE_HOME}/packaging/borrame
	popd
	echo "=> Make docs... done"
}

function update_project_version_numbers() {
	echo -e "=====================\n=> Updating version numbers for ${PROJECT}\n====================="
	if [ -z $KDE_VERSION ]; then
		FAIL "KDE_VERSION not set, unable to package"
	fi

	case ${PROJECT} in
		kdelibs*)
			pushd ${PROJECT}
			local CURRENT_MAJOR_VERSION=`grep -Eo "KDE_VERSION_MAJOR [0-9]*" CMakeLists.txt | cut -d" " -f2`
			local CURRENT_MINOR_VERSION=`grep -Eo "KDE_VERSION_MAJOR [0-9]*" CMakeLists.txt | cut -d" " -f2`
			local CURRENT_PATH_VERSION=`grep -Eo "KDE_VERSION_MAJOR [0-9]*" CMakeLists.txt | cut -d" " -f2`

			echo "=> Update CMakeLists.txt (KDE_VERSION_*)"
			sed -i -e "s:KDE_VERSION_MAJOR [0-9]*:KDE_VERSION_MAJOR ${MAJOR_VERSION}:" CMakeLists.txt
			sed -i -e "s:KDE_VERSION_MINOR [0-9]*:KDE_VERSION_MINOR ${MINOR_VERSION}:" CMakeLists.txt
			sed -i -e "s:KDE_VERSION_RELEASE [0-9]*:KDE_VERSION_RELEASE ${PATCH_VERSION}:" CMakeLists.txt

			echo "=> Update README"
			sed -i -e "s:version [0-9]*\.[0-9]*\.[0-9]* of the KDE libraries:version ${FULL_VERSION} of the KDE libraries:" README

			echo "=> Update cmake/modules/KDE4Defaults.cmake (GENERIC_LIB_VERSION, KDE_NON_GENERIC_LIB_VERSION)"
			sed -i -e "s:set(GENERIC_LIB_VERSION \"[0-9]*\.[0-9]*\.[0-9]*\"):set(GENERIC_LIB_VERSION \"${FULL_VERSION}\"):" cmake/modules/KDE4Defaults.cmake
			#sed -i -e "s:set(GENERIC_LIB_SOVERSION \"[0-9]*\"):set(GENERIC_LIB_SOVERSION \"${MAJOR_VERSION}\"):" cmake/modules/KDE4Defaults.cmake
			sed -i -e "s:set(KDE_NON_GENERIC_LIB_VERSION \"[0-9]*\.[0-9]*\.[0-9]*\"):set(KDE_NON_GENERIC_LIB_VERSION \"$((${MAJOR_VERSION}+1)).${MINOR_VERSION}.${PATCH_VERSION}\"):" cmake/modules/KDE4Defaults.cmake
			#sed -i -e "s:set(KDE_NON_GENERIC_LIB_SOVERSION \"[0-9]*\"):set(KDE_NON_GENERIC_LIB_SOVERSION \"$((${MAJOR_VERSION}+1))\"):" cmake/modules/KDE4Defaults.cmake
			popd
			;;
		kdepimlibs*)
			echo "=> Update CMakeLists.txt (KDEPIMLIBS_VERSION_*)"
			pushd ${PROJECT}
			sed -i -e "s:KDEPIMLIBS_VERSION_MAJOR [0-9]*:KDEPIMLIBS_VERSION_MAJOR ${MAJOR_VERSION}:" CMakeLists.txt
			sed -i -e "s:KDEPIMLIBS_VERSION_MINOR [0-9]*:KDEPIMLIBS_VERSION_MINOR ${MINOR_VERSION}:" CMakeLists.txt
			sed -i -e "s:KDEPIMLIBS_VERSION_RELEASE [0-9]*:KDEPIMLIBS_VERSION_RELEASE ${PATCH_VERSION}:" CMakeLists.txt
			popd
			;;
		kdepim*)
			echo "=> Update CMakeLists.modules (KDEPIM_DEV_VERSION, KDEPIM_VERSION)"
			pushd ${PROJECT}
			#sed -i -e "s:set(KDEPIM_DEV_VERSION.*):set(KDEPIM_DEV_VERSION ):" CMakeLists.txt
			sed -i -e "s:KDEPIM_VERSION \"[0-9]*\.[0-9]*\.[0-9]*\":KDEPIM_VERSION \"${FULL_VERSION}\":" CMakeLists.txt
			popd
			;;
		kdepim-runtime*)
			echo "Update CMakeLists.txt (KDEPIM_RUNTIME_DEV_VERSION, KDEPIM_RUNTIME_VERSION)"
			pushd ${PROJECT}
			sed -i -e "s:set([ ]*KDEPIM_RUNTIME_DEV_VERSION.*):set( KDEPIM_RUNTIME_DEV_VERSION ):" CMakeLists.txt
			sed -i -e "s:KDEPIM_RUNTIME_VERSION \"[0-9]*\.[0-9]*\.[0-9]*\":KDEPIM_RUNTIME_VERSION \"${FULL_VERSION}\"):" CMakeLists.txt
			popd
			;;
		kde-workspace*)
			echo "=> Update CMakeLists.txt (KDE4WORKSPACE_VERSION_*)"
			pushd ${PROJECT}
			sed -i -e "s:KDE4WORKSPACE_VERSION_MAJOR [0-9]*:KDE4WORKSPACE_VERSION_MAJOR ${MAJOR_VERSION}:" CMakeLists.txt
			sed -i -e "s:KDE4WORKSPACE_VERSION_MINOR [0-9]*:KDE4WORKSPACE_VERSION_MINOR ${MINOR_VERSION}:" CMakeLists.txt
			sed -i -e "s:KDE4WORKSPACE_VERSION_RELEASE [0-9]*:KDE4WORKSPACE_VERSION_RELEASE ${PATCH_VERSION}:" CMakeLists.txt

			if [[ ${PATCH_VERSION} == 0 ]]; then
				echo "=> Removing MALLOC_CHECK from startkde-cmake"
			fi
			popd
			;;
		kopete*)
			echo "=> Update kopeteversion.h"
			pushd ${PROJECT}
			local KOPETE_MAJOR_VERSION=`grep -Eo 'KOPETE_VERSION_MAJOR [0-9]+' kopeteversion.h | cut -d" " -f2`
			local KOPETE_MINOR_VERSION=`grep -Eo 'KOPETE_VERSION_MINOR [0-9]+' kopeteversion.h | cut -d" " -f2`
			local KOPETE_PATCH_VERSION=`grep -Eo 'KOPETE_VERSION_RELEASE [0-9]+' kopeteversion.h | cut -d" " -f2`
			
			if [[ -n ${CURRENT_MAJOR_VERSION} ]]; then
				KOPETE_MAJOR_VERSION=$(($KOPETE_MAJOR_VERSION + (${KDE_MAJOR_VERSION} - ${CURRENT_MAJOR_VERSION})))
				KOPETE_MINOR_VERSION=$(($KOPETE_MINOR_VERSION + (${KDE_MINOR_VERSION} - ${CURRENT_MINOR_VERSION})))
				KOPETE_PATCH_VERSION=$(($KOPETE_PATCH_VERSION + (${KDE_PATCH_VERSION} - ${CURRENT_PATCH_VERSION})))
			else
				if [[ ${PATH_VERSION} == 0 ]]; then
					KOPETE_MINOR_VERSION=$(($KOPETE_MINOR_VERSION + 1))
				else
					KOPETE_PATCH_VERSION=$(($KOPETE_PATCH_VERSION + 1))
				fi
			fi
			sed -i -E -e "s:#define KOPETE_VERSION_STRING \"[0-9]+.[0-9]+.[0-9]+\":#define KOPETE_VERSION_STRING \"${KOPETE_MAJOR_VERSION}.${KOPETE_MINOR_VERSION}.${KOPETE_PATCH_VERSION}\":" kopeteversion.h
			sed -i -E -e "s:#define KOPETE_VERSION_MAJOR [0-9]+:#define KOPETE_VERSION_MAJOR ${KOPETE_MAJOR_VERSION}:" kopeteversion.h
			sed -i -E -e "s:#define KOPETE_VERSION_MINOR [0-9]+:#define KOPETE_VERSION_MINOR ${KOPETE_MINOR_VERSION}:" kopeteversion.h
			sed -i -E -e "s:#define KOPETE_VERSION_RELEASE [0-9]+:#define KOPETE_VERSION_RELEASE ${KOPETE_PATCH_VERSION}:" kopeteversion.h

			popd
			;;
		*)
			;;
	esac
}

function update_branch_information {
	echo "=> Updating branch information..."
	sed -i -e "s:HEADURL=branches/KDE/[0-9]*\.[0-9]*/$1:HEADURL=branches/KDE/${MAJOR_MINOR_VERSION}/$1:" ${JENKINS_SLAVE_HOME}/packaging/versions
	# if branch KDE/${MAJOR_MINOR_VERSION} doesn't exists use master
	sed -i -e "s:KDE/[0-9]*\.[0-9]*:KDE/${MAJOR_MINOR_VERSION}:" ${JENKINS_SLAVE_HOME}/packaging/modules.git
	echo "=> Updating branch information... done"
}

function package_project() {
	echo -e "=====================\n=> Packaging a single project (${PROJECT})\n====================="
	pushd ${WORKSPACE}
	rm -rf build dirty sources borrame
	mkdir -p clean build dirty sources borrame
	create_packaging_helpers
	update_project_version_numbers
	make_docs
	package
	popd
}

function package_kde_sc() {
	echo -e "=====================\n=> Packaging KDE SC\n====================="
	echo "=> Using version: ${MAJOR_VERSION}.${MINOR_VERSION}.${PATCH_VERSION}"
	pushd ${WORKSPACE}
	rm -rf borrame
	rm -rf sources
	rm -rf dirty
	rm -rf build
	mkdir -p clean build dirty sources borrame

	update_branch_information

	echo -e "=====================\n=> Checking out/Updating all SVN based modules\n====================="
	#Checkout all SVN based modules
	BASE="svn://anonsvn.kde.org/home/kde" ${JENKINS_SLAVE_HOME}/packaging/checkout
	echo -e "=====================\n=> Cloning/Updating all Git based modules\n====================="
	#And now all git based
	BASE="git://anongit.kde.org/" ${JENKINS_SLAVE_HOME}/packaging/setup-git-modules.sh

	create_packaging_helpers

	local PACKAGES
	PACKAGES=`awk ' {print $1 }' ${JENKINS_SLAVE_HOME}/packaging/modules.git`

	for PROJECT in `cat ${JENKINS_SLAVE_HOME}/packaging/modules`; do
		PACKAGES="${PACKAGES} ${PROJECT}"
	done

	for PROJECT in ${PACKAGES} ${SVN_PACKAGES}; do
		if [[ "${PROJECT}" != "kde-l10n" ]]; then
			echo -e "=====================\n=> Processig ${PROJECT}\n====================="
			echo "=> Copying sources to 'dirty'..."
			cp -prl clean/${PROJECT}/ dirty
			echo "=> Copying sources to 'dirty'... done"
			pushd dirty
			update_project_version_numbers
			make_docs
			package
			popd
		fi
	done

	if [[ "$KDE_MAJOR_VERSION" == "4" ]] && [[ "$KDE_MINOR_VERSION" == "9" ]]; then
		${JENKINS_SLAVE_HOME}/packaging/pack_kdegames
	fi

	PROJECT="kde-l10n"
	echo -e "=====================\n=> Processig ${PROJECT} (SVN)\n====================="
	echo "=> Copying sources to 'dirty'..."
	mkdir -p ${WORKSPACE}/sources/${PROJECT}
	cp -prl clean/${PROJECT}/ dirty
	echo "=> Copying sources to 'dirty'... done"
	pushd dirty
	update_project_version_numbers
	make_docs
	package
	popd
	echo "=> Removing unqualified languages from packaging results..."
	pushd sources/kde-l10n
	for l in *.xz; do
		ll=${l##kde-l10n-}
		if [[ !`grep ${ll%%-${FULL_VERSION}.tar.xz} ../../language_list`]]; then
			echo "==> Removing ${l}"
			rm ${l}
		fi
	done
	echo "=> Removing unqualified languages from packaging results... done"
	popd

	create_checksums
	record_versions
}

function build_kde_sc_from_packages() {
	echo -e "=====================\n=> Building KDE SC from packaged sources\n====================="
	local SRCDIR=$1
	local PACKAGES
	pushd ${SRCDIR}
	PACKAGES=`ls -1 *-${FULL_VERSION}.tar.xz | sed -e "s:-${FULL_VERSION}.tar.xz::" -e 's:^:kde/:' | xargs`
	LANGUAGES=`ls -1 kde-l10n/kde-l10n-*-${FULL_VERSION}.tar.xz | sed -e "s:-${FULL_VERSION}.tar.xz::" | xargs`
	popd

	echo "=> Finding build order..."
	${JENKINS_SLAVE_HOME}/build-deps-parser.py ${PACKAGES}
	source ${WORKSPACE}/build-kde-org.dependency.order
	echo "=> Finding build order... done"

	rm -rf ${WORKSPACE}/install
	mkdir ${WORKSPACE}/install

	PREFIX="${WORKSPACE}/install"
	export PATH="${JENKINS_SLAVE_HOME}:${PREFIX}/bin:${PATH%:}:${COMMON_DEPS}/bin:${PREFIX}/Qt/${QT_STABLE_BRANCH}/bin"
	export LD_LIBRARY_PATH="${PREFIX}/lib64:${LD_LIBRARY_PATH%:}:${COMMON_DEPS}/lib64:${PREFIX}/Qt/${QT_STABLE_BRANCH}/lib"
	export PKG_CONFIG_PATH="${PREFIX}/share/pkgconfig:${PREFIX}/lib64/pkgconfig:${PKG_CONFIG_PATH%:}:${COMMON_DEPS}/share/pkgconfig:${COMMON_DEPS}/lib64/pkgconfig"
	export QT_PLUGIN_PATH="${PREFIX}/lib64/qt4/plugins:${PREFIX}/lib64/kde4/plugins:${QT_PLUGIN_PATH%:}:${COMMON_DEPS}"
	export XDG_DATA_DIRS="${PREFIX}/share:${XDG_DATA_DIRS%:}:/usr/local/share/:/usr/share:${COMMON_DEPS}/share"
	export XDG_CONFIG_DIRS="${PREFIX}/etc/xdg:${XDG_CONFIG_DIRS%:}:/etc/xdg:${COMMON_DEPS}/etc/xdg"
	export KDEDIRS="${PREFIX}:${KDEDIRS%:}"
	CMAKE_CMD_LINE="-DCMAKE_PREFIX_PATH=\"${CMAKE_PREFIX_PATH%:}\""
	export QML_IMPORT_PATH=${QML_IMPORT_PATH}
	export PYTHONPATH="${PYTHONPATH}:${COMMON_DEPS}/lib64/python2.7/site-packages:${COMMON_DEPS}/share/sip/"

	pushd ${WORKSPACE}/build
	for PROJECT in ${ORDERED_DEPENDENCIES} ${LANGUAGES}; do
		echo "=> Building ${PROJECT/kde\/}..."
		tar xJf ../sources/${PROJECT/kde\/}-${FULL_VERSION}.tar.xz || FAIL "Unable to unpack ${PROJECT/kde\/}"
		pushd ${PROJECT/kde\/}-${FULL_VERSION}
		rm -rf build
		mkdir build
		pushd build

		${JENKINS_SLAVE_HOME}/cmake.sh ${EXTRA_VARS} -DKDE4_BUILD_TESTS=ON -DLIB_SUFFIX=64 -DSIP_DEFAULT_SIP_DIR=${WORKSPACE}/install/share/sip/ -DCMAKE_INSTALL_PREFIX=${WORKSPACE}/install .. || FAIL "Unable to configure ${PROJECT/kde\/}"
		${JENKINS_SLAVE_HOME}/make.sh || FAIL "Unable to build ${PROJECT/kde\/}"
		${JENKINS_SLAVE_HOME}/make.sh install || FAIL "Unable to install ${PROJECT/kde\/}"
		popd
		popd
		rm -rf ${PROJECT/kde\/}/${FULL_VERSION}
		echo "=> Building ${PROJECT/kde\/}... done"
	done
}
