#!/bin/bash

BINDIR="$( cd "$( dirname "$0" )" && pwd )"
export JENKINS_SLAVE_HOME=${BINDIR}
echo "=> JENKINS_SLAVE_HOME=${JENKINS_SLAVE_HOME}"
if [ -z "${WORKSPACE}" ]; then
    echo "\$WORKSPACE not set!"
else
    source ${WORKSPACE}/environment-vars.sh
fi

echo "=> Getting running Xvfb instances"
pids=`pgrep Xvfb -U jenkins`
if [[ $? == 0 ]]; then
    echo "==> Pids found, killing"
    echo "${pids}"
    killall -u jenkins Xvfb
    rm -f /tmp/.X99-lock
fi
echo "=> Done"
echo "=> Getting running dbus instances"
pids=`pgrep dbus-daemon -U jenkins`
if [[ $? == 0 ]]; then
    echo "==> Pids found, killing"
    echo "${pids}"
    killall -u jenkins dbus-daemon
fi
echo "=> Done"

echo "=> Starting Xvfb"
export DISPLAY=:99
Xvfb :99 -ac &

echo "=> Starting dbus"
DBUS_LAUNCH=`which dbus-launch`
eval `${DBUS_LAUNCH} --sh-syntax`
echo "=> Checking operational status of dbus..."
qdbus

echo "=> Starting kdeinit..."
kdeinit4 &> /dev/null &
nepomukserver &> /dev/null &

echo "=> Waiting for startup of KDE processes to complete..."
sleep 30s
echo "=> Checking status of KDE processes..."
pgrep -l -U jenkins kdeinit4
pgrep -l -U jenkins nepomukserver

kbuildsycoca4 --noincremental

BUILD_DIR="${WORKSPACE}/build"
rm -f ${BUILD_DIR}/JUnitTestResults.xml
pushd ${BUILD_DIR}

sed -ie 's/TimeOut: .*/TimeOut: 20/' DartConfiguration.tcl
ctest -T Test --output-on-failure --no-compress-output
popd

${JENKINS_SLAVE_HOME}/ctesttojunit.py ${BUILD_DIR} ${JENKINS_SLAVE_HOME}/ctesttojunit.xsl > JUnitTestResults.xml

echo "=> Testing completed, shutting down processes..."
qdbus org.kde.NepomukServer /nepomukserver quit
killall -u jenkins kdeinit4 kded4 klauncher knotify4

echo "=> Waiting for KDE processes to shutdown..."
sleep 30s
echo "=> Checking status of KDE processes..."
pgrep -l -U jenkins kdeinit4
pgrep -l -U jenkins nepomukserver
pgrep -l -U jenkins kded4
pgrep -l -U jenkins knotify4
echo "=> done"
