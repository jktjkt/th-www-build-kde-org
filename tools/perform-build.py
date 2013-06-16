#!/usr/bin/python
import os
import sys
import time
import socket
import urllib
import argparse
import ConfigParser
from lxml import etree
from kdecilib import Project, ProjectManager, BuildManager, check_jenkins_environment

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control building and execution of tests in an automated manner.')
parser.add_argument('--project', type=str)
parser.add_argument('--branch', type=str)
parser.add_argument('--sources', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')
parser.add_argument('--base', type=str, choices=['qt5', 'qt4', 'common'], default='qt4')
# Parse the arguments
environmentArgs = check_jenkins_environment()
arguments = parser.parse_args( namespace=environmentArgs )

# Load the various configuration files
config = ConfigParser.SafeConfigParser( {'systemBase': arguments.base} )
configFiles =  ['config/build/global.cfg', 'config/build/{base}.cfg', 'config/build/{host}.cfg', 'config/build/{platform}.cfg']
configFiles += ['config/build/{project}/project.cfg', 'config/build/{project}/{base}.cfg', 'config/build/{project}/{host}.cfg', 'config/build/{project}/{platform}.cfg']
for confFile in configFiles:
	confFile = confFile.format( host=socket.gethostname(), base=arguments.base, platform=arguments.platform, project=arguments.project )
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

# Base handling: load special dependency data and ignored projects list
with open('config/base/%s' % config.get('General', 'systemBase'), 'r') as fileHandle:
	ProjectManager.setup_dependencies( fileHandle.readlines() )

with open('config/base/ignore', 'r') as fileHandle:
	ProjectManager.setup_ignored( fileHandle.readlines() )

# Load the list of ignored projects
with open('dependencies/build-script-ignore', 'r') as fileHandle:
	ProjectManager.setup_ignored( fileHandle.readlines() )

# Load the dependencies
with open('dependencies/dependency-data', 'r') as fileHandle:
	ProjectManager.setup_dependencies( fileHandle.readlines() )

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# Prepare the build manager
manager = BuildManager(project, arguments.branch, arguments.sources, config)

# Give out some information on what we are going to do...
print "\nKDE Continuous Integration Build"
print "== Building Project: %s - Branch %s" % (project.identifier, manager.projectBranch)
print "== Build Dependencies:"
for dependency, dependencyBranch in manager.dependencies:
	print "==== %s - Branch %s" %(dependency.identifier, dependencyBranch)

# Cleanup the source tree and apply any necessary patches if we have them
print "\n== Cleaning Source Tree\n"
manager.cleanup_sources()
print "\n== Applying Patches\n"
if not manager.apply_patches():
	sys.exit("Applying patches to project %s failed." % project.identifier)

# Sync all the dependencies
print "\n== Syncing Dependencies from Master Server\n"
if not manager.sync_dependencies():
	sys.exit("Syncing dependencies from master server for project %s failed." % project.identifier)

# Perform the build (including configure, post-configure, make and make install)
print "\n== Commencing Build Process\n"
if not manager.execute_build():
	sys.exit("Build step exited with non-zero code, assuming failure to build from source for project %s." % project.identifier)

# Deploy the newly completed build to the local tree as well as the master server
print "\n== Deploying Installation\n"
if not manager.deploy_installation():
	sys.exit("Deployment of completed installation failed for project %s." % project.identifier)

# Execute the tests
print "\n== Executing Tests\n"
manager.execute_tests()

# Run cppcheck
print "\n== Executing cppcheck\n"
manager.execute_cppcheck()

print "\n== Run Completed Successfully\n"
