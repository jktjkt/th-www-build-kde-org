#!/bin/bash -ex

function FAIL {
	# return if sourced and exit if executed
	[ "$0" != "bash" ] || return 1
	exit 1
}

if [ -z ${JENKINS_BRANCH} ]; then
	echo "=> JENKINS_BRANCH not set!"
	export JENKINS_BRANCH="master"
fi

if [ -z "${WORKSPACE}" ]; then
    echo "WORKSPACE not set!"
    FAIL
fi

if [ -z "${JENKINS_SLAVE_HOME}" ]; then
    echo "JENKINS_SLAVE_HOME not set!"
    FAIL
fi

pushd ${JENKINS_SLAVE_HOME}
`git fetch origin` || FAIL
`git checkout ${JENKINS_BRANCH}` || FAIL
`git merge --ff-only origin/${JENKINS_BRANCH}` || FAIL
`git log -1 HEAD` || FAIL
popd
