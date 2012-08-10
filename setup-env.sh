#!/bin/bash -e

function FAIL {
	# return if sourced and exit if executed
	[ "$0" != "bash" ] || return 1
	exit 1
}

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

echo -n "=>Setting up tools..."
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
echo "done"

echo -n "=>Setting up dependency info..."
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
echo "done"

${JENKINS_SLAVE_HOME}/setup-branch.sh
