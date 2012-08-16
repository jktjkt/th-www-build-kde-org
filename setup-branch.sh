#!/bin/bash -e

echo -e "\n=====================\n=> Setting up branch\n====================="

source ${JENKINS_SLAVE_HOME}/functions.sh

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
	rm -f jenkins-cli.jar
	wget http://sandbox.build.kde.org/jnlpJars/jenkins-cli.jar
	EXTERNAL_JOBS=`java -jar ./jenkins-cli.jar -i jenkins-private.key -s http://sandbox.build.kde.org groovy external_jobs.groovy`
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
	echo "=> Setting up git..."
	pushd ${JENKINS_SLAVE_HOME}	
	REPO_ADDRESS=`${JENKINS_SLAVE_HOME}/projects.kde.org.py resolve repo ${PROJECT}`
	popd
	echo "=> Setting up git... done"

	if [ ! -d ".git" ]; then
		git clone $REPO_ADDRESS .
	fi
	# If we are on the branch, this will not work...
	#git branch -D ${WANTED_BRANCH}
	echo "=> Using branch ${RESOLVED_BRANCH}"
	git branch --set-upstream --force jenkins origin/${RESOLVED_BRANCH}

	echo "=> Sleeping for $POLL_DELAY seconds to allow mirrors to sync"
	sleep $POLL_DELAY
fi

export_var KDE_PROJECT ${KDE_PROJECT}

echo -e "=> Handing over to Jenkins\n====================="