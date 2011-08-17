#!/bin/bash -x

BINDIR="$( cd "$( dirname "$0" )" && pwd )"
export JENKINS_SLAVE_HOME=${BINDIR}
echo "=> JENKINS_SLAVE_HOME=${JENKINS_SLAVE_HOME}"

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

echo "=> \${JENKINS_HOME} = ${JENKINS_HOME}"
if [[ -z ${KDE_DEVEL_PREFIX} ]]; then
    if [[ -z $1 ]]; then
        KDE_DEVEL_PREFIX="/home/jenkins"
    else
        KDE_DEVEL_PREFIX="$1"
    fi
fi
echo "=> \${KDE_DEVEL_PREFIX} = ${KDE_DEVEL_PREFIX}"

echo "=> Starting Xvfb"
export DISPLAY=:99
Xvfb :99 -ac &

echo "=> Setting up environment variables"

export INSTALL_ROOT=${KDE_DEVEL_PREFIX}/install
export KDE_INSTALL_ROOT=${INSTALL_ROOT}/master
export QT_INSTALL_ROOT=${INSTALL_ROOT}/qt4
export DEPS_INSTALL_ROOT=${INSTALL_ROOT}/deps

unset XDG_DATA_DIRS
unset XDG_CONFIG_DIRS

export KDEHOME=${KDE_DEVEL_PREFIX}/.kde
export PKG_CONFIG_PATH=${KDE_INSTALL_ROOT}/lib/pkgconfig:${QT_INSTALL_ROOT}/lib/pkgconfig:${DEPS_INSTALL_ROOT}/lib/pkgconfig:${PKG_CONFIG_PATH}
export QT_PLUGIN_PATH=${KDE_INSTALL_ROOT}/lib/kde4/plugins:${QT_PLUGIN_PATH}
export PATH=${KDE_INSTALL_ROOT}/bin:${QT_INSTALL_ROOT}/bin:${DEPS_INSTALL_ROOT}/bin:${PATH}
export LD_LIBRARY_PATH=${KDE_INSTALL_ROOT}/lib:${QT_INSTALL_ROOT}/lib:${DEPS_INSTALL_ROOT}/lib:${LD_LIBRARY_PATH}

export XDG_DATA_DIRS=${KDE_INSTALL_ROOT}/share:${DEPS_INSTALL_ROOT}/share
export XDG_CONFIG_DIRS=${KDE_INSTALL_ROOT}/etc/xdg:${DEPS_INSTALL_ROOT}/etc/xdg

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

BUILD_DIR="${JENKINS_SLAVE_HOME}/../build/${JOB_NAME}"
rm -f ${BUILD_DIR}/JUnitTestResults.xml
pushd ${BUILD_DIR}
sed -ie 's/TimeOut: .*/TimeOut: 20/' DartConfiguration.tcl
ctest -T Test --output-on-failure --no-compress-output
popd
${JENKINS_SLAVE_HOME}/ctesttojunit.py ${BUILD_DIR} ${JENKINS_SLAVE_HOME}/ctesttojunit.xsl > JUnitTestResults.xml

echo "=> Testing completed, shutting down processes..."
qdbus org.kde.NepomukServer /nepomukserver quit
killall -u jenkins kdeinit4 kded4 klauncher knotify4

