rm -f build\JUnitTestResults.xml
pushd build
sed -ie 's/TimeOut: .*/TimeOut: 20/' build/DartConfiguration.tcl
ctest -T Test --output-on-failure --no-compress-output
popd
${JENKINS_SLAVE_HOME}/ctesttojunit.py build ${JENKINS_SLAVE_HOME}/ctesttojunit.xsl > build/JUnitTestResults.xml
