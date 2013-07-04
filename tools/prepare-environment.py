#!/usr/bin/python
import os
import sys
import time
import shlex
import urllib
import argparse
import subprocess
from lxml import etree
from kdecilib import Project, ProjectManager, BuildManager, check_jenkins_environment, load_project_configuration

# Load our command line arguments
parser = argparse.ArgumentParser(description='Utility to initialize a git repository before handover to the build executor.')
parser.add_argument('--project', type=str)
parser.add_argument('--branch', type=str)
parser.add_argument('--sources', type=str)
parser.add_argument('--delay', type=int, default=10)
# Parse the arguments
environmentArgs = check_jenkins_environment()
arguments = parser.parse_args( namespace=environmentArgs )

# Load the various configuration files
config = load_project_configuration( arguments.project )

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

# Load the requested project
project = ProjectManager.lookup( arguments.project )
if project is None:
	sys.exit("Requested project %s was not found." % arguments.project)

# We do not need to perform any handling for general dependencies
if project.generalDependency:
	sys.exit()

# First we must wait for the anongit mirrors to settle
time.sleep( arguments.delay )

# Prepare the sources and handover to Jenkins
manager = BuildManager(project, arguments.branch, arguments.sources, config)
manager.checkout_sources()