#!/bin/bash -e

function FAIL {
	# return if sourced and exit if executed
	[ "$0" != "bash" ] || return 1
	exit 1
}

echo -e "\n=====================\n=> Setting up build environment\n====================="


if [ -z ${JENKINS_BRANCH} ]; then
	echo "=> JENKINS_BRANCH not set!"
	export JENKINS_BRANCH="master"
fi

if [ -z ${JENKINS_DEPENDENCY_BRANCH} ]; then
	echo "=> JENKINS_DEPENDENCY_BRANCH not set!"
	FAIL
fi

if [ -z "${WORKSPACE}" ]; then
    echo "WORKSPACE not set!"
    FAIL
fi

if [ -z "${JENKINS_SLAVE_HOME}" ]; then
    echo "JENKINS_SLAVE_HOME not set!"
    FAIL
fi

echo "=>Setting up tools..."
pushd ${JENKINS_SLAVE_HOME}
(
	if [ ! -d .git ]; then
		git clone git://anongit.kde.org/websites/build-kde-org .
	fi
	git fetch origin
	git checkout ${JENKINS_BRANCH}
	git merge --ff-only origin/${JENKINS_BRANCH}
	git log -1 HEAD
) || FAIL
popd
echo "=>Setting up tools... done"

echo "=>Setting up dependency info..."
mkdir -p ${JENKINS_SLAVE_HOME}/dependencies
pushd ${JENKINS_SLAVE_HOME}/dependencies
(
	if [ ! -d ".git" ]; then
		git clone git://anongit.kde.org/kde-build-metadata .
	fi
	git fetch origin
	git checkout ${JENKINS_DEPENDENCY_BRANCH}
	git merge --ff-only origin/${JENKINS_DEPENDENCY_BRANCH}
	git log -1 HEAD
) || FAIL
popd
echo "=>Setting up dependency info... done"

echo "=> Setting up ECMA 262 test data"
mkdir -p ${JENKINS_SLAVE_HOME}/ecma262
pushd ${JENKINS_SLAVE_HOME}/ecma262
(
	if [ ! -d ".hg" ]; then
		hg clone http://hg.ecmascript.org/tests/test262/ .
	fi
	hg pull -u
)
popd
echo "=> Setting up ECMA 262 test data... done"

${JENKINS_SLAVE_HOME}/setup-branch.sh
