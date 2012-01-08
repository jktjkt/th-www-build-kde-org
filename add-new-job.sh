#!/bin/bash -x

env

if [[ -d /var/lib/jenkins/jobs/$PROJECT_$BRANCH ]]; then
    echo "Job already exists"
    exit 1
fi
wget http://build.kde.org/jnlpJars/jenkins-cli.jar || exit 1

sed -e "s:\${PROJECT}:$_PROJECT:g" -e "s:\${PROJECTGROUP}:$_PROJECTGROUP:g" -e "s:\${BRANCH}:$_BRANCH:g" -e "s:\${MAILNOTIFIER}:$_MAILNOTIFIER:g" $JENKINS_SLAVE_HOME/new_job_skel.xml > newjobconfig.xml || exit 1

echo java -jar jenkins-cli.jar -s http://build.kde.org/ create-job ${PROJECT}_${BRANCH/\/-} <newjobconfig.xml
