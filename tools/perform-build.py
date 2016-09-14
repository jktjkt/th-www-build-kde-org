#!/usr/bin/python
import sys
import argparse
from kdecilib import *

def sys_exit_override(*args, **kwargs):
    global _real_sys_exit
    if os.environ.has_key('TH_RESULT_FILE') and len(args) and args[0] != 0:
        with open(os.environ['TH_RESULT_FILE'], 'wb') as fp:
            fp.write(args[0])
    _real_sys_exit(*args, **kwargs)

_real_sys_exit = sys.exit
sys.exit = sys_exit_override


# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control building and execution of tests in an automated manner.')
parser.add_argument('--project', type=str)
parser.add_argument('--branchGroup', type=str, default='latest-qt4')
parser.add_argument('--sources', type=str)
parser.add_argument('--variation', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++',
                                                     'darwin-mavericks',
                                                     'windows-mingw-w64',
                                                     'th-rhel7-gcc',
                                                     'th-rhel7-qt52',
                                                     'th-rhel7-qt55',
                                                     'th-rhel7-qt56',
                                                     'th-rhel7-qt57',
                                                     'th-rhel7-qt58',
                                                     'th-rhel7-qt58-asan',
                                                    ], default='linux64-g++')

# Parse the arguments
environmentArgs = check_jenkins_environment()
arguments = parser.parse_args( namespace=environmentArgs )

# Load our configuration, projects and dependencies
config = load_project_configuration( arguments.project, arguments.branchGroup, arguments.platform, arguments.variation )
if not load_projects( 'kde_projects.xml', 'http://projects.kde.org/kde_projects.xml', 'config/projects', 'dependencies/logical-module-structure' ):
	sys.exit("Failure to load projects - unable to continue")
load_project_dependencies( 'config/base/', arguments.branchGroup, 'dependencies/' )

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# Prepare the build manager
manager = BuildManager(project, arguments.branchGroup, arguments.sources, config)

# Give out some information on what we are going to do...
print "\nKDE Continuous Integration Build"
print "== Building Project: %s - Branch %s" % (project.identifier, manager.projectBranch)
print "== Build Dependencies:"
for dependency, dependencyBranch in manager.dependencies:
	print "==== %s - Branch %s" %(dependency.identifier, dependencyBranch)

# Apply any necessary patches if we have them
print "\n== Applying Patches"
if not manager.apply_patches():
	sys.exit("FAILURE_patch")

# Sync all the dependencies
print "\n== Syncing Dependencies from Master Server\n"
if not manager.sync_dependencies():
	sys.exit("FAILURE_deps")

# Configure the build
print "\n== Configuring Build\n"
if not manager.configure_build():
	sys.exit("FAILURE_configure")

# Build the project
print "\n== Commencing the Build\n"
if not manager.compile_build():
	sys.exit("FAILURE_build")

# Install the project
print "\n== Installing the Build\n"
if not manager.install_build():
	sys.exit("FAILURE_install")

if not os.environ.has_key('TH_JOB_NAME') or (os.environ['TH_JOB_NAME'].startswith('rebuilddep-') and os.environ['TH_JOB_NAME'].find('-release-minimal-') == -1):
	# Deploy the newly completed build to the local tree as well as the master server
	print "\n== Deploying Installation\n"
	if not manager.deploy_installation():
		sys.exit("Deployment of completed installation failed.")
else:
	print "\n== This is a check job, not deploying installation\n"

# Execute the tests
print "\n== Executing Tests\n"
tests_ok = manager.execute_tests()
if manager.die_asap:
	if tests_ok:
		sys.exit(0)
	else:
		sys.exit("FAILURE_tests")

# Run cppcheck
print "\n== Executing cppcheck\n"
manager.execute_cppcheck()

# Perform a lcov processing run
print "\n== Performing lcov processing\n"
manager.generate_lcov_data_in_cobertura_format()

# Extract dependency data from CMake
print "\n== Extracting dependency information from CMake\n"
manager.extract_dependency_information()
manager.extract_cmake_dependency_metadata()

print "\n== Run Completed Successfully\n"
