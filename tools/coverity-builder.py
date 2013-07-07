#!/usr/bin/python
import argparse
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
bulkManager.compile_builds()