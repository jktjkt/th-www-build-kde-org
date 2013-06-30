#!/usr/bin/python
import os
import sys
import time
import urllib
import argparse
from lxml import etree
from kdecilib import Project, ProjectManager, BulkBuildManager, check_jenkins_environment, load_project_configuration

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control bulk building of projects in a automated manner.')
parser.add_argument('--sourceRoot', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')
# Parse the arguments
arguments = parser.parse_args()

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
for base in ['qt5', 'qt4', 'common']:
	with open('config/base/%s' % base, 'r') as fileHandle:
		ProjectManager.setup_dependencies( fileHandle, globalBase = base )

with open('config/base/ignore', 'r') as fileHandle:
	ProjectManager.setup_ignored( fileHandle )

# Load the list of ignored projects
with open('dependencies/build-script-ignore', 'r') as fileHandle:
	ProjectManager.setup_ignored( fileHandle )

# Load the dependencies
with open('dependencies/dependency-data', 'r') as fileHandle:
	ProjectManager.setup_dependencies( fileHandle )

# Prepare the bulk build manager
bulkManager = BulkBuildManager('config/coverity/projects.list', arguments.sourceRoot, arguments.platform)

# Give out some information on what we are going to do...
print "\nKDE Coverity Submission Build"
print "== Building Projects:"
for manager in bulkManager.projectManagers:
	print "==== %s - Branch %s" %(manager.project.identifier, manager.projectBranch)

# Cleanup the source tree and apply any necessary patches if we have them
print "\n== Preparing Sources\n"
bulkManager.prepare_sources()

# Sync all the dependencies
print "\n== Syncing Dependencies from Master Server\n"
if not bulkManager.sync_dependencies():
	sys.exit("Syncing dependencies from master server failed.")

# Configure the builds
print "\n== Configuring Builds\n"
bulkManager.configure_builds()

# Invoke the builder via cov-build...
command = bulkManager.projectManagers[0].config.get('QualityCheck', 'covBuildCommand')
command = command.format( sourceRoot=arguments.sourceRoot, platform=arguments.platform )
command = shlex.split( command )

# Execute the command which is part of the build execution process
subprocess.call( command, stdout=sys.stdout, stderr=sys.stderr, cwd=os.getcwd() )

print "\n== Run Completed Successfully\n"
