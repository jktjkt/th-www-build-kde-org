#!/usr/bin/python
import sys
import argparse
from kdecilib import *

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control building and execution of tests in an automated manner.')
parser.add_argument('--project', type=str, required=True)
parser.add_argument('--branch', type=str, required=True)
parser.add_argument('--sources', type=str, required=True)
parser.add_argument('--variation', type=str)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')
parser.add_argument('--base', type=str, choices=availableBases, default='qt4')
arguments = parser.parse_args()

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
