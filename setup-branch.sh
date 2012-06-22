#!/bin/bash -ex

function FAIL {
    echo $@
    # return if sourced and exit if executed
    [ $0 != "bash" ] || return 1
    exit 1
}

if [ -z "${JOB_NAME}" ]; then
     echo "JOB_NAME not set!"
     FAIL
fi

if [ -z "${BRANCH}" ]; then
     echo "BRANCH not set!"
     FAIL
fi
 
if [ -z "${JENKINS_SLAVE_HOME}" ]; then
     echo "JENKINS_SLAVE_HOME not set!"
     FAIL
fi

WANTED_BRANCH=${BRANCH}

JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"
#WANTED_BRANCH="${JOB_NAME##*_}"

if [[ "${PROJECT}" == "Qt" ]]; then
	if [[ "$WANTED_BRANCH" == "stable" ]]; then
		RESOLVED_BRANCH=${QT_STABLE_BRANCH}
	elif [[ "$WANTED_BRANCH" == "master" ]]; then
		RESOLVED_BRANCH=${QT_FUTURE_BRANCH}
	elif [[ "${WANTED_BRANCH}" == "legacy" ]]; then
		RESOLVED_BRANCH=${QT_LEGACY_BRANCH}
	else
		FAIL "Unknown Qt branch ${WANTED_BRANCH}"
	fi
else
	pushd ${JENKINS_SLAVE_HOME}
	RESOLVED_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${WANTED_BRANCH}`
	popd
fi

REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`

pushd ${WORKSPACE}
if [ ! -d ".git" ]; then
	git clone $REPO_ADDRESS .
fi
git branch -D ${WANTED_BRANCH}
git branch --track ${WANTED_BRANCH} origin/${RESOLVED_BRANCH}

echo "=> Sleeping for $POLL_DELAY seconds to allow mirrors to sync"
sleep $POLL_DELAY
echo "=> Handing over to Jenkins"
