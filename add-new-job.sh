#!/bin/bash -x

env

if [[ -d ../jenkins-server/jobs/$_PROJECT_$_BRANCH ]]; then
    echo "Job already exists"
    exit 1
fi

rm jenkins-cli.jar
wget http://build.kde.org/jnlpJars/jenkins-cli.jar || exit 1

sed -e "s:\${PROJECT}:$_PROJECT:g" -e "s:\${PROJECTGROUP}:$_PROJECTGROUP:g" -e "s:\${BRANCH}:$_BRANCH:g" -e "s:\${MAILNOTIFIER}:$_MAILNOTIFIER:g" $JENKINS_SLAVE_HOME/new_job_skel.xml > newjobconfig.xml || exit 1

java -jar jenkins-cli.jar -i jenkins-private.key -s http://build.kde.org/ create-job ${_PROJECT}_${_BRANCH/\/-} <newjobconfig.xml
