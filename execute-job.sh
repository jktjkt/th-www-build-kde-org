#!/bin/bash
cd ${JENKINS_SLAVE_HOME}
python -u tools/perform-build.py
