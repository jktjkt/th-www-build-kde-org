#!/usr/bin/python
import os
import sys
import shlex
import argparse
import subprocess
from kdecilib import *

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control bulk building of projects in a automated manner.')
parser.add_argument('--sourceRoot', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')

# Parse the arguments
arguments = parser.parse_args()

# Load our projects and dependencies
load_projects( 'kde_projects.xml', 'http://projects.kde.org/kde_projects.xml', 'config/projects' )
load_project_dependencies( availableBases, 'config/base/', 'dependencies/' )

# Prepare the bulk build manager
bulkManager = BulkBuildManager('config/coverity/projects.list', arguments.sourceRoot, arguments.platform)

# Give out some information on what we are going to do...
print "\nKDE Coverity Submission Build"
print "== Building Projects:"
for manager in bulkManager.projectManagers:
	print "==== %s - Branch %s - With Base %s" %(manager.project.identifier, manager.projectBranch, manager.config.get('General', 'systemBase'))

# Cleanup the source tree and apply any necessary patches if we have them
print "\n== Preparing Sources\n"
bulkManager.prepare_sources()

# Sync all the dependencies
print "\n== Syncing Dependencies from Master Server\n"
bulkManager.sync_dependencies()

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
