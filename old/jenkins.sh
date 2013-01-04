#!/bin/bash
# vim: set sw=4 sts=4 et tw=80 :

BINDIR="$( cd "$( dirname "$0" )" && pwd )"
export JENKINS_SLAVE_HOME=${BINDIR}
echo "=> JENKINS_SLAVE_HOME=${JENKINS_SLAVE_HOME}"
JENKINSSERVER=build.kde.org:80

echo "=> Getting running slave instances"
pids=`pgrep -fU jenkins slave.jar`
if [[ $? == 0 ]]; then
	echo "==> Pids found, killing"
	echo "${pids}"
	pkill -fU jenkins slave.jar
fi
echo "=> Done"
if [[ -z ${JENKINS_HOME} ]]; then
        JENKINS_HOME=${HOME}
fi
echo "=> \${JENKINS_HOME} = ${JENKINS_HOME}"

echo "=> Downloading Jenkins slave client"

cd ${JENKINS_SLAVE_DIR}
rm *.jar
wget ${JENKINSSERVER}/jnlpJars/slave.jar

java -jar slave.jar
