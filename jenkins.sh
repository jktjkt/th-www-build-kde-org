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

if [[ -z ${JENKINS_HOME} ]]; then
        JENKINS_HOME=${HOME}
fi
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
#for t in 1 2 3 4 5; do
#	sleep 1
#done
echo "=> Starting dbus"
DBUS_LAUNCH=`which dbus-launch`
eval `${DBUS_LAUNCH} --sh-syntax`
echo "DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}';"
echo "export DBUS_SESSION_BUS_ADDRESS;"
echo "DBUS_SESSION_BUS_PID=${DBUS_SESSION_BUS_PID};"

echo "Test env setup complete"

cd ${JENKINS_SLAVE_DIR}
rm *.jar
wget ${JENKINSSERVER}/jnlpJars/slave.jar

export KDE_INSTALL_ROOT=${KDE_DEVEL_PREFIX}/install
export QT_INSTALL_ROOT=${KDE_INSTALL_ROOT}/qt4
export DEPS_INSTALL_ROOT=${KDE_INSTALL_ROOT}/deps

unset XDG_DATA_DIRS
unset XDG_CONFIG_DIRS

export KDEHOME=${KDE_DEVEL_PREFIX}/.kde
export PKG_CONFIG_PATH=${KDE_INSTALL_PREFIX}/lib/pkgconfig:${QT_INSTALL_PREFIX}/lib/pkgconfig:${DEPS_INSTALL_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}
export QT_PLUGIN_PATH=${KDE_INSTALL_PREFIX}/lib/kde4/plugins:${QT_PLUGIN_PATH}
export PATH=${KDE_INSTALL_PREFIX}/bin:${QT_INSTALL_PREFIX}/bin:${DEPS_INSTALL_PREFIX}/bin:${PATH}
export LD_LIBRARY_PATH=${KDE_INSTALL_PREFIX}/lib:${QT_INSTALL_PREFIX}/lib:${DEPS_INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH}

export XDG_DATA_HOME=${KDE_INSTALL_PREFIX}/share
export XDG_CONFIG_HOME=${KDE_INSTALL_PREFIX}/etx/xdg
export XDG_DATA_DIRS=${XDG_DATA_HOME}
export XDG_CONFIG_DIRS=${XDG_CONFIG_HOME}

echo "============================================="
echo "============== env =========================="
env
echo "============================================="
echo "=> Starting slave"
java -jar slave.jar
