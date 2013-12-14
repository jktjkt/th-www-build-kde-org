#!/usr/bin/python
import sys
import argparse
from kdecilib import *

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control building and execution of tests in an automated manner.')
parser.add_argument('--project', type=str, required=True)
parser.add_argument('--branchGroup', type=str, required=True)
parser.add_argument('--variation', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++'], default='linux64-g++')
arguments = parser.parse_args()

# Load our configuration, projects and dependencies
config = load_project_configuration( arguments.project, arguments.branchGroup, arguments.platform, arguments.variation )
load_projects( 'kde_projects.xml', 'http://projects.kde.org/kde_projects.xml', 'config/projects', 'dependencies/logical-module-structure' )
load_project_dependencies( 'config/base/', arguments.branchGroup, 'dependencies/' )

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# Prepare the build manager
manager = BuildManager(project, arguments.branchGroup, '/tmp', config)
environment = manager.generate_environment(True)

# We care about these environment variables
neededVariables = [
	'CMAKE_PREFIX_PATH', 'KDEDIRS', 'PATH', 'LD_LIBRARY_PATH', 'PKG_CONFIG_PATH', 'PYTHONPATH',
	'PERL5LIB', 'QT_PLUGIN_PATH', 'QML_IMPORT_PATH', 'QML2_IMPORT_PATH', 'XDG_DATA_DIRS',
	'XDG_CONFIG_DIRS', 'QMAKEFEATURES', 'XDG_CURRENT_DESKTOP'
]

# Generate the shell format environment file, suitable for sourcing
for variable in neededVariables:
	if variable in environment:
		print 'export %s="%s"' % (variable, environment[variable])
