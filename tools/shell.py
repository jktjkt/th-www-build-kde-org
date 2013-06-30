#!/usr/bin/python
import os
import time
import urllib
import argparse
from lxml import etree
from kdecilib import Project, ProjectManager, BuildManager, load_project_configuration

# Our choices
baseOptions = ['qt5', 'qt4', 'common']

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to control building and execution of tests in an automated manner.')
parser.add_argument('--project', type=str, required=True)
parser.add_argument('--branch', type=str, required=True)
parser.add_argument('--sources', type=str, required=True)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')
parser.add_argument('--base', type=str, choices=baseOptions, default='qt4')
arguments = parser.parse_args()

# Load the various configuration files
config = load_project_configuration( arguments.project, arguments.base, arguments.platform )

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
for base in baseOptions:
	with open('config/base/%s' % base, 'r') as fileHandle:
		ProjectManager.setup_dependencies( fileHandle, systemBase = base )

with open('config/base/ignore', 'r') as fileHandle:
	ProjectManager.setup_ignored( fileHandle )

# Load the list of ignored projects
with open('dependencies/build-script-ignore', 'r') as fileHandle:
	ProjectManager.setup_ignored( fileHandle )

# Load the dependencies
with open('dependencies/dependency-data', 'r') as fileHandle:
	ProjectManager.setup_dependencies( fileHandle )

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# Prepare the build manager
manager = BuildManager(project, arguments.branch, arguments.sources, config)
