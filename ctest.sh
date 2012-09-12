#!/bin/bash

BINDIR="$( cd "$( dirname "$0" )" && pwd )"
export JENKINS_SLAVE_HOME=${BINDIR}
echo "=> JENKINS_SLAVE_HOME=${JENKINS_SLAVE_HOME}"
if [ -z "${WORKSPACE}" ]; then
    echo "\$WORKSPACE not set!"
else
	source ${WORKSPACE}/build-kde-org.environment
fi

rm -f ${BUILD_DIR}/JUnitTestResults.xml
rm -rf ${BUILD_DIR}/Testing
pushd ${BUILD_DIR}

ctest -N | grep "Total Tests: 0"
if [[ $? == 0 ]]; then
    echo "=> No tests found"
cat <<EOB > ${BUILD_DIR}/JUnitTestResults.xml
<?xml version="1.0"?>
<testsuite>
  <properties>
  </properties>
  <testcase name="successful-build-no-tests-found" classname="TestSuite" time="0.0121629"/>
  <system-out></system-out>
</testsuite>
EOB
else
	echo "=> Making sure Xvfb is up..."
	export DISPLAY=:99
	pids=`pgrep Xvfb -U jenkins`
	if [[ $? != 0 ]]; then
	    echo "==> Xvfb not running, starting..."
	    rm -f /tmp/.X99-lock
            Xvfb :99 -ac &
	fi
	echo "=> Done"
	
	echo "=> Setting up runtime environment"
	RUNTIME_BRANCH=`echo $DEPS | sed -e "s,.*kde/kdelibs=\([A-Z|a-z|\/|0-9|\.]*\).*,\1,g"`
	if [[ "${RUNTIME_BRANCH}" != '' ]]; then
		PREFIX="${ROOT}/install/kde/kde-runtime/${RUNTIME_BRANCH}"
		
		export CMAKE_PREFIX_PATH="${PREFIX}:${CMAKE_PREFIX_PATH}"
		export PATH="${PREFIX}/bin:${PATH}"
		export LD_LIBRARY_PATH="${PREFIX}/lib64:${LD_LIBRARY_PATH}"
		export PKG_CONFIG_PATH="${PREFIX}/share/pkgconfig:${PREFIX}/lib64/pkgconfig:${PKG_CONFIG_PATH}"
		export QT_PLUGIN_PATH="${PREFIX}:${QT_PLUGIN_PATH}"
		export XDG_DATA_DIRS="${PREFIX}/share:${XDG_DATA_DIRS}"
		export XDG_CONFIG_DIRS="${PREFIX}/etc/xdg:${XDG_CONFIG_DIRS}"
		export KDEDIRS="${PREFIX}:${KDEDIRS}"

		export QML_IMPORT_PATH="${PREFIX}/lib64/qt4/imports:${QML_IMPORT_PATH}"
		export QT_PLUGIN_PATH="${PREFIX}/lib/qt4/plugins/designer:${QT_PLUGIN_PATH}"
		export PYTHONPATH="${PREFIX}/lib64/python2.7/site-packages/:${PREFIX}/share/sip/:${PYTHONPATH}"
	fi
	echo "=> Done: $KDEDIRS"
	
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

	echo "==> kbuildsycoca4 servicetypes search paths:"
	kde4-config --path servicetypes

	kbuildsycoca4 --noincremental

	sed -ie 's/TimeOut: .*/TimeOut: 60/' DartConfiguration.tcl

	echo "==> TEST is using the following env."
	env
	echo "==> /TEST env"

	ctest -T Test --output-on-failure --no-compress-output
	popd

	${JENKINS_SLAVE_HOME}/ctesttojunit.py ${BUILD_DIR} ${JENKINS_SLAVE_HOME}/ctesttojunit.xsl > JUnitTestResults.xml

	echo "=> Testing completed, shutting down processes..."
	qdbus org.kde.NepomukServer /nepomukserver quit
	#killall -u jenkins kdeinit4 kded4 klauncher knotify4

	echo "=> Waiting for KDE processes to shutdown..."
	sleep 30s
	echo "=> Checking status of KDE processes..."
	pgrep -l -U jenkins kdeinit4
	pgrep -l -U jenkins nepomukserver
	pgrep -l -U jenkins kded4
	pgrep -l -U jenkins knotify4
	echo "=> done"
fi

touch ${BUILD_DIR}/JUnitTestResults.xml
