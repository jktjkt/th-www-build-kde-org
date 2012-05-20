#!/bin/bash -x

if [ -z ${JENKINS_BRANCH} ]; then
	echo "=> JENKINS_BRANCH not set!"
	export JENKINS_BRANCH="origin/master"
fi

if [ -z "${WORKSPACE}" ]; then
    echo "WORKSPACE not set!"
    FAIL
fi

function FAIL {
	# return if sourced and exit if executed
	[ $0 ~= "bash" ] || return 1
	exit 1
}

`git fetch origin` && FAIL
`git checkout ${JENKINS_BRANCH}` && FAIL
`git merge --ff-only ${JENKINS_BRANCH}` && FAIL
`git log -1 HEAD`
