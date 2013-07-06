#!/usr/bin/python
import sys
import argparse
from kdecilib import *

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control building and execution of tests in an automated manner.')
parser.add_argument('--project', type=str)
parser.add_argument('--branch', type=str)
parser.add_argument('--sources', type=str)
parser.add_argument('--variation', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')
parser.add_argument('--base', type=str, choices=availableBases, default='qt4')

# Parse the arguments
environmentArgs = check_jenkins_environment()
arguments = parser.parse_args( namespace=environmentArgs )

# Load our configuration, projects and dependencies
config = load_project_configuration( arguments.project, arguments.base, arguments.platform, arguments.variation )
load_projects( 'kde_projects.xml', 'http://projects.kde.org/kde_projects.xml', 'config/projects' )
load_project_dependencies( availableBases, 'config/base/', 'dependencies/' )

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
print "\n== Applying Patches"
if not manager.apply_patches():
	sys.exit("Applying patches to project %s failed." % project.identifier)

# Sync all the dependencies
print "\n== Syncing Dependencies from Master Server\n"
if not manager.sync_dependencies():
	sys.exit("Syncing dependencies from master server for project %s failed." % project.identifier)

# Configure the build
print "\n== Configuring Build\n"
if not manager.configure_build():
	sys.exit("Configure step exited with non-zero code, assuming failure to configure for project %s." % project.identifier)

# Build the project
print "\n== Commencing the Build\n"
if not manager.compile_build():
	sys.exit("Compiliation step exited with non-zero code, assuming failure to build from source for project %s." % project.identifier)

# Install the project
print "\n== Installing the Build\n"
if not manager.install_build():
	sys.exit("Installation step exited with non-zero code, assuming failure to install from source for project %s." % project.identifier)

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
