#!/bin/bash -x
# vim: set sw=4 sts=4 et tw=80 :
#===============================================================================
#
#          FILE:  ctest-new.sh
# 
#         USAGE:  As a build task in Jenkins/Hudson, should be run after the
#                 real build.
# 
#   DESCRIPTION:  Performs the following tasks:
#                 1: Start a KDE unit test environment
#                 2: Runs ctest with appropriate args
#                 3: Converts the resulting ctest results to junit compatable
#                    as that is what Jenkins/Hudson requires
# 
#        AUTHOR:  Torgny Nyblom <nyblom@kde.org>
#       COMPANY:  KDE e.V.
#       VERSION:  1.0
#       CREATED:  08/23/2011 08:19:54 PM CEST
#===============================================================================

############################################################
# Possible bug incase of more then one executor per slave  #
# Then the test environment might be recreated or destoyed #
# behind a builds back                                     #
############################################################
. ./environment-vars.sh

BINDIR="$( cd "$( dirname "$0" )" && pwd )"

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

echo "Test env setup complete"

echo "============================================="
echo "============== env =========================="
env
echo "============================================="

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

