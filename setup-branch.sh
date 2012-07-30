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
     echo -e "\n=> BRANCH not set!"
     echo -e "=> Defaulting to master"
     BRANCH="master"
fi
 
if [ -z "${JENKINS_SLAVE_HOME}" ]; then
     echo "JENKINS_SLAVE_HOME not set!"
     FAIL
fi

WANTED_BRANCH=${BRANCH}

JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"
#WANTED_BRANCH="${JOB_NAME##*_}"

KDE_PROJECT=1

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
	rm -f jenkins-cli.jar
	wget http://sandbox.build.kde.org/jnlpJars/jenkins-cli.jar
	EXTERNAL_JOBS=`java -jar ./jenkins-cli.jar -i jenkins-private.key -s http://sandbox.build.kde.org groovy external_jobs.groovy`
	if `echo ${EXTERNAL_JOBS} | grep ${PROJECT}`; then
		KDE_PROJECT=0
		unset BRANCH
	else
		pushd ${JENKINS_SLAVE_HOME}
		RESOLVED_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${WANTED_BRANCH}`
		popd
	fi
fi

if [[ ${KDE_PROJECT} ]]; then
	REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`

	pushd ${WORKSPACE}
	if [ ! -d ".git" ]; then
		git clone $REPO_ADDRESS .
	fi
	# If we are on the branch, this will not work...
	#git branch -D ${WANTED_BRANCH}
	git branch --set-upstream ${WANTED_BRANCH} origin/${RESOLVED_BRANCH}

	echo "=> Sleeping for $POLL_DELAY seconds to allow mirrors to sync"
	sleep $POLL_DELAY
	echo "=> Handing over to Jenkins"
fi