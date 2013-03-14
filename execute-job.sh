#!/bin/bash
ulimit -c unlimited

cd ${JENKINS_SLAVE_HOME}
python -u tools/perform-build.py
