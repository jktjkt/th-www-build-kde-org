#!/usr/bin/python
import sys
import os
import subprocess

# Settings
if sys.platform == "win32":
	JENKINS_SLAVE_HOME="C:/Jenkins/scripts"
else:
	JENKINS_SLAVE_HOME=os.getenv("HOME") + "/scripts"
JENKINS_BRANCH="production"
JENKINS_DEPENDENCY_BRANCH="master"

def getRepository(repoPath, repoUrl, repoBranch="master"):
	if not os.path.exists(repoPath):
		os.mkdir(repoPath)

	originalDir = os.getcwd()
	os.chdir(repoPath)

	if not os.path.exists(".git"):
		subprocess.call("git clone " + repoUrl + " .", shell=True)

	subprocess.call("git fetch origin", shell=True)
	subprocess.call("git checkout " + repoBranch, shell=True)
	subprocess.call("git merge --ff-only origin/" + repoBranch, shell=True)

	os.chdir(originalDir)

getRepository(JENKINS_SLAVE_HOME, "git://anongit.kde.org/kde-build-metadata", JENKINS_BRANCH)
getRepository(os.path.join(JENKINS_SLAVE_HOME, "dependencies"), "git://anongit.kde.org/kde-build-metadata", JENKINS_DEPENDENCY_BRANCH)
getRepository(os.path.join(JENKINS_SLAVE_HOME, "poppler-test-data"), "git://git.freedesktop.org/git/poppler/test")
getRepository(os.path.join(JENKINS_SLAVE_HOME, "kapidox"), "git://anongit.kde.org/kapidox")
