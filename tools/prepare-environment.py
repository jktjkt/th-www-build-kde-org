#!/usr/bin/python
import os
import sys
import time
import shlex
import socket
import urllib
import argparse
import subprocess
import ConfigParser
from lxml import etree
from kdecilib import Project, ProjectManager, BuildManager, check_jenkins_environment

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to initialize a git repository before handover to the build executor.')
parser.add_argument('--project', type=str)
parser.add_argument('--branch', type=str)
parser.add_argument('--sources', type=str)
parser.add_argument('--delay', type=int, default=10)
# Parse the arguments
environmentArgs = check_jenkins_environment()
arguments = parser.parse_args( namespace=environmentArgs )

# Load the various configuration files
config = ConfigParser.SafeConfigParser()
configFiles =  ['config/build/global.cfg', 'config/build/{host}.cfg']
configFiles += ['config/build/{project}/project.cfg', 'config/build/{project}/{host}.cfg']
for confFile in configFiles:
	confFile = confFile.format( host=socket.gethostname(), project=arguments.project )
	config.read( confFile )

# Download the list of projects if necessary
project_file = 'kde_projects.xml'
if not os.path.exists(project_file) or time.time() > os.path.getmtime(project_file) + 60*60:
	urllib.urlretrieve('http://projects.kde.org/kde_projects.xml', project_file)

# Now load the list of projects into the project manager
with open('kde_projects.xml', 'r') as fileHandle:
	ProjectManager.load_projects( etree.parse(fileHandle) )

# Load special projects
for dirname, dirnames, filenames in os.walk('config/projects'):
	for filename in filenames:
		filePath = os.path.join( dirname, filename )
		ProjectManager.load_extra_project( filePath )

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# We do not need to perform any handling for general dependencies
if project.generalDependency:
	sys.exit()

# First we must wait for the anongit mirrors to settle
time.sleep( arguments.delay )

# Does the git repository exist?
gitDirectory = os.path.join( arguments.sources, '.git' )
if not os.path.exists(gitDirectory):
	# Clone the repository
	command = config.get('Source', 'gitCloneCommand').format( url=project.url )
	try:
		subprocess.check_call( shlex.split(command), cwd=arguments.sources )
	except subprocess.CalledProcessError:
		sys.exit("Failed to clone git repository.")

# Update the git repository
fetchCommand = config.get('Source', 'gitFetchCommand')
try:
	subprocess.check_call( shlex.split(fetchCommand), cwd=arguments.sources )
except subprocess.CalledProcessError:
	sys.exit("Failed to fetch git repository.")

# Ensure our desired branch is in place
branch = project.resolve_branch( arguments.branch )
fetchCommand = config.get('Source', 'gitSetBranchCommand').format( targetBranch=branch )
try:
	subprocess.check_call( shlex.split(fetchCommand), cwd=arguments.sources )
except subprocess.CalledProcessError:
	sys.exit("Failed to set required repository branch.")
