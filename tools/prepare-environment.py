#!/usr/bin/python
import sys
import time
import argparse
from kdecilib import *

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to initialize a git repository before handover to the build executor.')
parser.add_argument('--project', type=str)
parser.add_argument('--branch', type=str)
parser.add_argument('--sources', type=str)
parser.add_argument('--delay', type=int, default=10)
parser.add_argument('--platform', type=str, choices=['linux64-g++', 'win32-mingw-cross'], default='linux64-g++')
parser.add_argument('--base', type=str, choices=availableBases, default='qt4')

# Parse the arguments
environmentArgs = check_jenkins_environment()
arguments = parser.parse_args( namespace=environmentArgs )

# Load the various configuration files, and the projects
config = load_project_configuration( arguments.project, arguments.base, arguments.platform )
load_projects( 'kde_projects.xml', 'http://projects.kde.org/kde_projects.xml', 'config/projects' )

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# First we must wait for the anongit mirrors to settle
time.sleep( arguments.delay )

# Prepare the sources and handover to Jenkins
manager = BuildManager(project, arguments.branch, arguments.sources, config)
manager.checkout_sources()