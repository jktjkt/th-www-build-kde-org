#!/bin/bash -e

##
## A few functions to help us...
##
function FAIL {
	# return if sourced and exit if executed
	[ "$0" != "bash" ] || return 1
	exit 1
}

##
## Perform some sanity tests
##
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

echo -e "\n=====================\n=> Setting up branch\n====================="

# Purge the environment from the previous build
# (otherwise they indefinitely stack, making a dependency mess)
rm -f ${WORKSPACE}/build-kde-org.environment
source ${JENKINS_SLAVE_HOME}/functions.sh

# Determine the branch we want to build...
if [[ -n ${BRANCH} ]]; then
	WANTED_BRANCH=${BRANCH}
else
	WANTED_BRANCH="${JOB_NAME##*_}"
fi

JOB_NAME=${JOB_NAME/test-/}
PROJECT="${JOB_NAME%%_*}"

KDE_PROJECT="true"

echo "=> Resolving branch..."
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
	if [[ ! -f "jenkins-cli.jar" ]]; then
		wget http://${MASTER}:${HTTP_PORT:-80}/jnlpJars/jenkins-cli.jar
	fi

	EXTERNAL_JOBS=`java -jar ./jenkins-cli.jar -i jenkins-private.key -s http://${MASTER}:${HTTP_PORT:-80} groovy external_jobs.groovy`
	echo "=> External projects: ${EXTERNAL_JOBS}"
	if `echo "${EXTERNAL_JOBS}" | grep -q -- "${PROJECT}"`; then
		echo "=> Non KDE project"
		KDE_PROJECT="false"
		unset BRANCH
	else
		echo "=> KDE project"
		RESOLVED_BRANCH=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve branch ${PROJECT} ${WANTED_BRANCH}`
	fi
	popd
fi
echo "=> Resolving branch... ${RESOLVED_BRANCH}"

if [[ "${KDE_PROJECT}" == "true" ]]; then
	echo "=> Sleeping for $POLL_DELAY seconds to allow mirrors to sync"
	sleep $POLL_DELAY

	echo "=> Setting up git..."
	pushd ${JENKINS_SLAVE_HOME}
	REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`
	popd
	echo "=> Setting up git... done"

	if [ ! -d ".git" ]; then
		git clone $REPO_ADDRESS .
	fi
	git fetch
	echo "=> Using branch ${RESOLVED_BRANCH}"
	git branch --set-upstream --force jenkins origin/${RESOLVED_BRANCH}
fi

export_var KDE_PROJECT ${KDE_PROJECT}

echo -e "=====================\n=> Handing over to Jenkins\n=====================\n"
