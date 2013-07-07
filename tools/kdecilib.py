# Python library to help manage and run the KDE Continuous Integration system
import re
import os
import sys
import time
import copy
import shlex
import urllib
import shutil
import socket
import fnmatch
import argparse
import subprocess
import ConfigParser
import multiprocessing
from lxml import etree
from collections import defaultdict

# Bases we suggest projects use
availableBases = ['qt5', 'qt4', 'common']

class ProjectManager(object):
	# Projects which we know, keyed by their identifier
	_projects = {}
	# Regex for the dependency rules
	_dependencyRuleRe = re.compile(r"""
		(?P<project>[^\[]+)
		\s*
		(?:
			\[
				(?P<project_branch>[^ ]+)
			\]
		)?
		\s*
		:
		\s*
		(?P<ignore_dependency>-)?
		(?P<dependency>[^\[]+)
		\s*
		(:?
			\[
				(?P<dependency_branch>[^ ]+)
			\]
		)?
		""",re.X)

	# Sets up a project from a configuration file
	@staticmethod
	def load_extra_project( projectFilename ):
		# Read the project configuration
		projectData = ConfigParser.SafeConfigParser()
		projectData.read( projectFilename )

		# Determine if we already know a project by this name (ie. override rather than create)
		identifier = projectData.get('Project', 'identifier')
		project = ProjectManager.lookup( identifier )
		if project is None:
			project = Project()
			project.identifier = identifier
			ProjectManager._projects[ project.identifier ] = project

		# Are we overriding the path?
		if projectData.has_option('Project', 'path'):
			project.path = projectData.get('Project', 'path')

		# Are we overriding the url?
		if projectData.has_option('Project', 'url'):
			project.url = projectData.get('Project', 'url')

		# Are we changing the general dependency state?
		if projectData.has_option('Project', 'generalDependency'):
			project.generalDependency = projectData.getboolean('Project', 'generalDependency')

		# Are we registering any symbolic branches?
		if projectData.has_section('SymbolicBranches'):
			for symName in projectData.options('SymbolicBranches'):
				project.symbolicBranches[ symName ] = projectData.get('SymbolicBranches', symName)

		# If the symbolic branch 'trunk' was set we should also set 'master' to the same
		if 'trunk' in project.symbolicBranches:
			project.symbolicBranches['master'] = project.symbolicBranches['trunk']

	# Load the kde_projects.xml data in
	@staticmethod
	def load_projects( xmlData ):
		# Get a list of all repositories, then create projects for them
		for repoData in xmlData.iterfind('.//repo'):
			# Grab the actual project xml item
			projectData = repoData.getparent()

			# Create the new project and set the bare essentials
			project = Project()
			project.identifier = projectData.get('identifier')
			project.path = projectData.find('path').text
			project.url = repoData.find('url[@protocol="git"]').text

			# What branches has this project got?
			for branchItem in repoData.iterfind('branch'):
				# Maybe this branch is invalid?
				if branchItem.text is None or branchItem.text == 'none':
					continue

				# Is it a symbolic branch?
				if branchItem.get('i18n') != None:
					symName = branchItem.get('i18n')
					project.symbolicBranches[symName] = branchItem.text

				# Must be a normal branch then
				project.branches.append( branchItem.text )

			# If the symbolic branch 'trunk' was set we should also set 'master' to the same
			if 'trunk' in project.symbolicBranches:
				project.symbolicBranches['master'] = project.symbolicBranches['trunk']

			# Register this project now - all setup is completed
			ProjectManager._projects[ project.identifier ] = project

	# Setup ignored project metadata
	@staticmethod
	def setup_ignored( ignoreData ):
		# First, remove any empty lines as well as comments
		ignoreList = [ project.strip() for project in ignoreData if project.find("#") == -1 and project.strip() ]
		# Now mark any listed project as ignored
		for entry in ignoreList:
			project = ProjectManager.lookup( entry )
			project.ignore = True

	# Setup the dependencies from kde-build-metadata.git
	@staticmethod
	def setup_dependencies( depData, systemBase = None ):
		for depEntry in depData:
			# Cleanup the dependency entry and remove any comments
			depEntry = depEntry.strip()
			commentPos = depEntry.find("#")
			if commentPos >= 0:
				depEntry = depEntry[0:commentPos]

			# Prepare to extract the data and skip if the extraction fails
			match = ProjectManager._dependencyRuleRe.search( depEntry )
			if not match:
				continue

			# Determine which project is being assigned the dependency
			projectName = match.group('project').lower()
			project = ProjectManager.lookup( projectName )
			# Validate it (if the project lookup failed and it is not dynamic, it must be invalid)
			if project == None and projectName[-1] != '*':
				continue

			# Ensure we know the dependency - if it is marked as "ignore" then we skip this
			dependencyName = match.group('dependency').lower()
			dependency = ProjectManager.lookup( dependencyName )
			if dependency == None or dependency.ignore:
				continue

			# Are any branches specified for the project or dependency?
			projectBranch = dependencyBranch = '*'
			if match.group('project_branch'):
				projectBranch = match.group('project_branch')
			if match.group('dependency_branch'):
				dependencyBranch = match.group('dependency_branch')

			# Is this a global dynamic project?
			if systemBase is not None and projectName[-1] == '*':
				dependencyEntry = ( projectName, projectBranch, dependency, dependencyBranch )
				# Is it negated or not?
				if match.group('ignore_dependency'):
					Project.globalNegatedDeps[ systemBase ].append( dependencyEntry )
				else:
					Project.globalDependencies[ systemBase ].append( dependencyEntry )
			# Is this a dynamic project?
			elif projectName[-1] == '*':
				dependencyEntry = ( projectName, projectBranch, dependency, dependencyBranch )
				# Is it negated or not?
				if match.group('ignore_dependency'):
					Project.dynamicNegatedDeps.append( dependencyEntry )
				else:
					Project.dynamicDependencies.append( dependencyEntry )
			else:
				dependencyEntry = ( dependency, dependencyBranch )
				# Is it negated or not?
				if match.group('ignore_dependency'):
					project.negatedDeps[ projectBranch ].append( dependencyEntry )
				else:
					project.dependencies[ projectBranch ].append( dependencyEntry )

	# Lookup the given project name
	@staticmethod
	def lookup( projectName ):
		# We may have been passed a path, reduce it down to a identifier
		splitted = projectName.split('/')
		identifier = splitted[-1]
		# Now we try to return the desired project
		try:
			return ProjectManager._projects[identifier]
		except Exception:
			return

class Project(object):
	# Lists of "dynamic dependencies" and "dynamic negated dependencies" which apply to multiple projects
	globalDependencies = defaultdict(list)
	globalNegatedDeps = defaultdict(list)
	dynamicDependencies = []
	dynamicNegatedDeps = []

	# Setup our defaults
	def __init__(self):
		# The identifier, path and repository url are simply not set
		self.identifier = self.path = self.url = None
		# We are not an ignored project by default
		self.ignore = False
		# We are not a general dependency by default
		self.generalDependency = False
		# We have no branches or symbolic branches
		self.branches = []
		self.symbolicBranches = {}
		# We have no dependencies or negated dependencies
		self.dependencies = defaultdict(list)
		self.negatedDeps = defaultdict(list)

	# Give ourselves a pretty name
	def __repr__(self):
		return "<Project instance with identifier %s>" % self.identifier

	# Determine the actual name of the desired branch
	def resolve_branch(self, branchName):
		# Do we have a symbolic branch for the desired branch name?
		if branchName in self.symbolicBranches:
			return self.symbolicBranches[ branchName ]

		# Do we have a global override symbolic branch?
		if '*' in self.symbolicBranches:
			return self.symbolicBranches['*']

		# Does the branch actually exist?
		if branchName in self.branches:
			return branchName

		# The branch does not actually exist?!
		return 'master'

	# Return a list of dependencies of ourselves
	def determine_dependencies(self, desiredBranch, systemBase, includeSubDeps = True):
		# Prepare: Combine all dynamic dependencies and negations for processing
		allDynamicDeps = Project.globalDependencies[systemBase] + Project.dynamicDependencies
		allNegatedDynamicDeps = Project.globalNegatedDeps[systemBase] + Project.dynamicNegatedDeps

		# Prepare: Get the list of dynamic dependencies and negations which apply to us
		dynamicDeps = self._resolve_dynamic_dependencies( desiredBranch, allDynamicDeps )
		negatedDynamic = self._resolve_dynamic_dependencies( desiredBranch, allNegatedDynamicDeps )

		# Start our list of dependencies
		# Run the list of dynamic dependencies against the dynamic negations to do so
		ourDeps = finalDynamic = self._negate_dependencies( desiredBranch, dynamicDeps, negatedDynamic )

		# Add the project level dependencies to the list of our dependencies
		# Then run the list of our dependencies against the project negations
		ourDeps = self._negate_dependencies( desiredBranch, ourDeps + self.dependencies['*'], self.negatedDeps['*'] )

		# Add the branch level dependencies to the list of our dependencies
		# Then run the list of our dependencies against the branch negations
		ourDeps = self._negate_dependencies( desiredBranch, ourDeps + self.dependencies[ desiredBranch ], self.negatedDeps[ desiredBranch ] )

		# Ensure the current project is not listed (due to a dynamic dependency for instance)
		ourDeps = [(project, branch) for project, branch in ourDeps if project != self]

		# Add the dependencies of our dependencies if requested
		# Dynamic dependencies are excluded otherwise it will be infinitely recursive
		if includeSubDeps:
			toLookup = set(ourDeps) - set(finalDynamic)
			for dependency, dependencyBranch in toLookup:
				ourDeps = ourDeps + dependency.determine_dependencies(dependencyBranch, systemBase, includeSubDeps = True)
			for dependency, dependencyBranch in finalDynamic:
				ourDeps = ourDeps + dependency.determine_dependencies(dependencyBranch, systemBase, includeSubDeps = False)

		# Re-ensure the current project is not listed 
		# Dynamic dependency resolution of sub-dependencies may have re-added it
		ourDeps = [(project, branch) for project, branch in ourDeps if project != self]

		# Ensure we don't have any duplicates
		return list(set(ourDeps))

	def _resolve_dynamic_dependencies(self, desiredBranch, dynamicDeps):
		# Go over the dynamic dependencies list we have and see if we match
		projectDeps = []
		for dynamicName, dynamicBranch, dependency, dependencyBranch in dynamicDeps:
			# First we need to see if the dynamic name matches against our path
			if not fnmatch.fnmatch( self.path, dynamicName ):
				continue

			# Next - make sure the dynamicBranch is compatible with our desired branch name
			if dynamicBranch != desiredBranch and dynamicBranch != '*':
				continue

			# We match this - add it
			dependencyEntry = ( dependency, dependencyBranch )
			projectDeps.append( dependencyEntry )

		return projectDeps

	def _resolve_dependency_branch(self, branchName, dependentBranch):
		# Do we need to help it find out the branch it should be using?
		if branchName == '*':
			branchName = dependentBranch

		# Resolve the branch name in case it is symbolic or otherwise special
		return self.resolve_branch(branchName)

	def _negate_dependencies(self, desiredBranch, dependentProjects, negatedProjects):
		# First we go over both lists and resolve the branch name
		resolvedDependencies = [(project, project._resolve_dependency_branch(branch, desiredBranch)) for project, branch in dependentProjects]
		resolvedNegations =    [(project, project._resolve_dependency_branch(branch, desiredBranch)) for project, branch in negatedProjects]

		# Remove any dependencies which have been negated
		return list( set(resolvedDependencies) - set(resolvedNegations) )

class BuildManager(object):
	# Make sure we have our configuration and the project we are building available
	def __init__(self, project, projectBranch, projectSources, configuration):
		# Save them for later use
		self.project = project
		self.projectSources = projectSources
		self.config = configuration
		# Resolve the branch
		self.projectBranch = project.resolve_branch( projectBranch )
		# Get the list of dependencies to ensure we only build it once
		systemBase = self.config.get('General', 'systemBase')
		self.dependencies = project.determine_dependencies( self.projectBranch, systemBase )
		# We set the installPrefix now for convenience access elsewhere
		self.installPrefix = self.project_prefix( self.project, self.projectBranch )

	# Determine the proper prefix (either local or remote) where a project is installed
	def project_prefix(self, project, desiredBranch, local = True, includeHost = True, specialArguments = {}):
		# Determine the appropriate prefix
		prefix = self.config.get('General', 'installPrefix', vars=specialArguments)
		if not local and includeHost:
			prefix = self.config.get('General', 'remoteHostPrefix', vars=specialArguments)
		elif not local:
			prefix = self.config.get('General', 'remotePrefix', vars=specialArguments)
		
		# Do we have a proper Project instance which is not a general dependency?
		if isinstance(project, Project) and not project.generalDependency:
			return os.path.join( prefix, project.path, desiredBranch )
		# Maybe we have a proper Project instance which is a general dependency?
		elif isinstance(project, Project) and project.generalDependency:
			return os.path.join( prefix, project.path )
		# Maybe the project has still been provided as a string?
		elif isinstance(desiredBranch, str):
			return os.path.join( prefix, project, desiredBranch )
		# Final last-ditch fallback (should not happen)
		else:
			return os.path.join( prefix, project )

	def build_directory(self):
		# Maybe we have a project which prefers a in-source build?
		if self.config.getboolean('Build', 'inSourceBuild'):
			return self.projectSources

		# Assume an out-of-source build if it does not want an in-source build
		return os.path.join( self.projectSources, 'build' )

	def perform_rsync(self, source, destination, specialArguments = {}):
		# Get the rsync command
		rsyncCommand = self.config.get('General', 'rsyncCommand', vars=specialArguments)
		rsyncCommand = shlex.split( rsyncCommand )
		# Add the source and destination to our arguments
		rsyncCommand.append( source + '/' )
		rsyncCommand.append( destination )
		# Execute rsync and wait for it to finish
		process = subprocess.Popen( rsyncCommand, stdout=sys.stdout, stderr=sys.stderr )
		process.wait()
		# Indicate our success
		return process.returncode == 0

	def run_build_commands(self, buildCommands):
		# Prepare, and load parameters we will need later
		cpuCount = multiprocessing.cpu_count()
		buildDirectory = self.build_directory()
		installPath = os.path.join( self.projectSources, 'install' )

		# Prepare the environment
		# We need to ensure that 'make install' will deploy to the appropriate directory
		buildEnv = self.generate_environment()
		buildEnv['DESTDIR'] = buildEnv['INSTALL_ROOT'] = installPath

		# Actually invoke the commands
		for command in buildCommands:
			# Put the appropriate tokens in place
			# {instPrefix} = Directory where the project should be installed
			# {sources} = Base directory where the project sources are located
			# {loadLevel} = The desired maxmium load level during the build
			# {jobCount} = The appropriate number of jobs which should be started during a build
			command = command.format( instPrefix=self.installPrefix, sources=self.projectSources, loadLevel=cpuCount, jobCount=cpuCount + 1 )
			command = shlex.split( command )

			# Execute the command which is part of the build execution process
			try:
				process = subprocess.check_call( command, stdout=sys.stdout, stderr=sys.stderr, cwd=buildDirectory, env=buildEnv )
			except subprocess.CalledProcessError:
				# Abort if it fails to complete
				return False

		# We are successful
		return True

	# Sync all of our dependencies from the master server
	def sync_dependencies(self):
		# Sync the shared common dependencies
		hostPath = self.project_prefix( 'shared', None, local=False, specialArguments={'systemBase': 'common'} )
		localPath = self.project_prefix( 'shared', None, specialArguments={'systemBase': 'common'} )
		# Make sure the local path exists (otherwise rsync will fail)
		if not os.path.exists( localPath ):
			os.makedirs( localPath )
		if not self.perform_rsync( source=hostPath, destination=localPath ):
			return False

		# Sync the project and shared system base dependencies
		candidates = self.dependencies + [('shared', None)]
		for candidate, candidateBranch in candidates:
			# Determine the host (source) and local (destination) directories we are syncing
			hostPath = self.project_prefix( candidate, candidateBranch, local=False )
			localPath = self.project_prefix( candidate, candidateBranch )
			# Make sure the local path exists (otherwise rsync will fail)
			if not os.path.exists( localPath ):
				os.makedirs( localPath )
			# Execute the command
			if not self.perform_rsync( source=hostPath, destination=localPath ):
				return False

		return True

	# Generate environment variables for configure / building / testing
	def generate_environment(self, runtime = False):
		# Build the list of projects we need to include
		requirements = self.dependencies
		# For runtime (ie. running tests) we need to include ourselves too and kde-runtime as well
		if runtime:
			# First we try to find kde-runtime - use the same branch as the kdelibs dependency
			kdeRuntime = ProjectManager.lookup('kde-runtime')
			kdelibsDep = [(project, branch) for project, branch in self.dependencies if project.identifier == 'kdelibs']
			if kdelibsDep and kdeRuntime:
				libsProject, libsBranch = kdelibsDep[0]
				requirements.append( (kdeRuntime, libsBranch) )
			# Now we add ourselves
			requirements.append( (self.project, self.projectBranch) )

		# Turn the list of requirements into a list of prefixes
		reqPrefixes = [self.project_prefix( requirement, requirementBranch ) for requirement, requirementBranch in requirements]
		# Add the shared dependency directories
		reqPrefixes.append( self.project_prefix('shared', None) )
		reqPrefixes.append( self.project_prefix('shared', None, specialArguments={'systemBase': 'common'}) )

		# Generate the environment
		envChanges = defaultdict(list)
		for reqPrefix in reqPrefixes:
			# Make sure the prefix exists
			if not os.path.exists(reqPrefix):
				continue

			# Setup CMAKE_PREFIX_PATH
			envChanges['CMAKE_PREFIX_PATH'].append( reqPrefix )
			# Setup KDEDIRS
			envChanges['KDEDIRS'].append( reqPrefix )

			# Setup PATH
			extraLocation = os.path.join( reqPrefix, 'bin' )
			if os.path.exists( extraLocation ):
				envChanges['PATH'].append(extraLocation)

			# Handle those paths which involve $prefix/lib*
			for libraryDirName in ['lib', 'lib32', 'lib64']:
				# Do LD_LIBRARY_PATH
				extraLocation = os.path.join( reqPrefix, libraryDirName )
				if os.path.exists( extraLocation ):
					envChanges['LD_LIBRARY_PATH'].append(extraLocation)

				# Now do PKG_CONFIG_PATH
				extraLocation = os.path.join( reqPrefix, libraryDirName, 'pkgconfig' )
				if os.path.exists( extraLocation ):
					envChanges['PKG_CONFIG_PATH'].append(extraLocation)

				# Now we check PYTHONPATH
				extraLocation = os.path.join( reqPrefix, libraryDirName, 'python2.7/site-packages' )
				if os.path.exists( extraLocation ):
					envChanges['PYTHONPATH'].append(extraLocation)

				# Next is PERL5LIB
				extraLocation = os.path.join( reqPrefix, libraryDirName, 'perl5/site_perl/5.14.2/x86_64-linux-thread-multi/' )
				if os.path.exists( extraLocation ):
					envChanges['PERL5LIB'].append(extraLocation)

				# Next up is QT_PLUGIN_PATH
				for pluginDirName in ['qt4/plugins', 'kde4/plugins', 'plugins']:
					extraLocation = os.path.join( reqPrefix, libraryDirName, pluginDirName )
					if os.path.exists( extraLocation ):
						envChanges['QT_PLUGIN_PATH'].append(extraLocation)

				# Finally we do QML_IMPORT_PATH
				for pluginDirName in ['qt4/imports', 'kde4/imports', 'imports']:
					extraLocation = os.path.join( reqPrefix, libraryDirName, pluginDirName )
					if os.path.exists( extraLocation ):
						envChanges['QML_IMPORT_PATH'].append(extraLocation)

				# And to finish, QML2_IMPORT_PATH
				for pluginDirName in ['qml']:
					extraLocation = os.path.join( reqPrefix, libraryDirName, pluginDirName )
					if os.path.exists( extraLocation ):
						envChanges['QML2_IMPORT_PATH'].append(extraLocation)

			# Setup PKG_CONFIG_PATH
			extraLocation = os.path.join( reqPrefix, 'share/pkgconfig' )
			if os.path.exists( extraLocation ):
				envChanges['PKG_CONFIG_PATH'].append(extraLocation)

			# Setup XDG_DATA_DIRS
			extraLocation = os.path.join( reqPrefix, 'share' )
			if os.path.exists( extraLocation ):
				envChanges['XDG_DATA_DIRS'].append(extraLocation)

			# Setup XDG_CONFIG_DIRS
			extraLocation = os.path.join( reqPrefix, 'etc/xdg' )
			if os.path.exists( extraLocation ):
				envChanges['XDG_CONFIG_DIRS'].append(extraLocation)

			# Setup PYTHONPATH
			extraLocation = os.path.join( reqPrefix, 'share/sip' )
			if os.path.exists( extraLocation ):
				envChanges['PYTHONPATH'].append( extraLocation )

		# Finally, we can merge this into the real environment
		clonedEnv = copy.deepcopy(os.environ.__dict__['data'])
		for variableName, variableEntries in envChanges.iteritems():
			# Join them
			newEntry = ':'.join( variableEntries )
			# If the variable already exists in the system environment, we prefix ourselves on
			if variableName in clonedEnv:
				newEntry = '%s:%s' % (newEntry, clonedEnv[variableName])
			# Set the variable into our cloned environment
			clonedEnv[variableName] = newEntry

		# Return the dict of the cloned environment, suitable for use with subprocess.Popen
		return clonedEnv

	def checkout_sources(self, doCheckout = False):
		# We cannot handle general dependencies here
		if self.project.generalDependency:
			return True

		# Does the git repository exist?
		gitDirectory = os.path.join( self.projectSources, '.git' )
		if not os.path.exists(gitDirectory):
			# Clone the repository
			command = self.config.get('Source', 'gitCloneCommand')
			command = command.format( url=self.project.url )
			try:
				subprocess.check_call( shlex.split(command), cwd=self.projectSources )
			except subprocess.CalledProcessError:
				return False

		# Update the git repository
		command = self.config.get('Source', 'gitFetchCommand')
		try:
			subprocess.check_call( shlex.split(command), cwd=self.projectSources )
		except subprocess.CalledProcessError:
			return False

		# Ensure our desired branch is in place
		command = self.config.get('Source', 'gitSetBranchCommand')
		command = command.format( targetBranch=self.projectBranch )
		try:
			subprocess.check_call( shlex.split(command), cwd=self.projectSources )
		except subprocess.CalledProcessError:
			return False

		# Do we need to checkout the sources too?
		if doCheckout:
			# Check the sources out
			command = self.config.get('Source', 'gitCheckoutCommand')
			command = command.format( branch=self.projectBranch )
			try:
				subprocess.check_call( shlex.split(command), cwd=self.projectSources )
			except subprocess.CalledProcessError:
				return False

		# All successful
		return True

	def cleanup_sources(self):
		# Prepare Git/Subversion paths
		gitDirectory = os.path.join( self.projectSources, '.git' )
		svnDirectory = os.path.join( self.projectSources, '.svn' )
		bzrDirectory = os.path.join( self.projectSources, '.bzr' )

		# Which directories are we cleaning?
		pathsToClean = [self.projectSources]

		# Maybe it is a Git repository?
		if os.path.exists( gitDirectory ):
			command = self.config.get('Source', 'gitCleanCommand')
			# Because Git is silly, we have to build it a special list of paths to clean
			pathsToClean = []
			for root, dirs, files in os.walk( self.projectSources, topdown=False ):
				if '.git' in dirs:
					pathsToClean.append( root )
		# Maybe it is a SVN checkout?
		elif os.path.exists( svnDirectory ):
			command = self.config.get('Source', 'svnRevertCommand')
		# Maybe it is a BZR checkout?
		elif os.path.exists( bzrDirectory ):
			command = self.config.get('Source', 'bzrCleanCommand')
		# Nothing for us to do
		else:
			return

		for path in pathsToClean:
			process = subprocess.Popen(command, shell=True, cwd=path)
			process.wait()

		return

	def apply_patches(self):
		# Do we have anything to apply?
		patchesDir = os.path.join( self.config.get('General', 'scriptsLocation'), 'patches', self.project.identifier, self.projectBranch )
		if not os.path.exists(patchesDir):
			print "=== No patches to apply\n"
			return True

		# Iterate over the patches and apply them
		command = shlex.split( self.config.get('Source', 'patchCommand') )
		for dirname, dirnames, filenames in os.walk(patchesDir):
			for filename in filenames:
				# Get the full path to the patch
				patchPath = os.path.join( dirname, filename )
				# Apply the patch
				try:
					print "=== Applying: %s\n" % patchPath
					process = subprocess.check_call( command + [patchPath], stdout=sys.stdout, stderr=sys.stderr, cwd=self.projectSources )
					print ""
				except subprocess.CalledProcessError:
					# Make sure the patch applied successfully - if it failed, then we should halt here
					return False

		return True

	def configure_build(self):
		# Determine the directory we will perform the build in and make sure it exists
		buildDirectory = self.build_directory()
		if not os.path.exists( buildDirectory ):
			os.makedirs( buildDirectory )

		# Get the initial configuration command
		command = self.config.get('Build', 'configureCommand')
		buildCommands = [ command ]

		# Next comes the post configure command
		if self.config.has_option('Build', 'postConfigureCommand'):
			command = self.config.get('Build', 'postConfigureCommand')
			buildCommands.append( command )

		# Do the configure
		return self.run_build_commands( buildCommands )

	def compile_build(self):
		# Load the command and run it
		command = self.config.get('Build', 'makeCommand')
		return self.run_build_commands( [command] )

	def install_build(self):
		# Perform the installation
		command = self.config.get('Build', 'makeInstallCommand')
		buildCommands = [ command ]

		# Final command which is needed to finish up the installation
		if self.config.has_option('Build', 'postInstallationCommand'):
			command = self.config.get('Build', 'postInstallationCommand')
			buildCommands.append( command )

		# Do the installation
		if not self.run_build_commands( buildCommands ):
			return False

		# Do we need to run update-mime-database?
		buildEnv = self.generate_environment()
		installRoot = os.path.join( self.projectSources, 'install', self.installPrefix[1:] )
		mimeDirectory = os.path.join( installRoot, 'share', 'mime' )
		if os.path.exists( mimeDirectory ):
			# Invoke update-mime-database
			command = self.config.get('Build', 'updateMimeDatabaseCommand')
			subprocess.call( shlex.split(command), stdout=sys.stdout, stderr=sys.stderr, cwd=installRoot, env=buildEnv )

		# None of the commands failed, so assume we succeeded
		return True

	def deploy_installation(self):
		# Make sure the local destination exists
		if not os.path.exists( self.installPrefix ):
			os.makedirs( self.installPrefix )

		# If we are moving a general dependency, then we need to disable deletion
		specialArguments = {}
		if self.project.generalDependency:
			specialArguments['rsyncExtraArgs'] = ''

		# First we have to transfer the install from the "install root" to the actual install location
		sourcePath = os.path.join( self.projectSources, 'install', self.installPrefix[1:] )
		if not self.perform_rsync( source=sourcePath, destination=self.installPrefix, specialArguments=specialArguments ):
			return False

		# Next we ensure the remote directory exists
		serverPath = self.project_prefix( self.project, self.projectBranch, local=False, includeHost=False )
		command = self.config.get('General', 'createRemotePathCommand').format( remotePath=serverPath )
		process = subprocess.Popen( shlex.split(command), stdout=sys.stdout, stderr=sys.stderr)
		process.wait()

		# Now we sync the actual install up to the master server so it can be used by other build slaves
		serverPath = self.project_prefix( self.project, self.projectBranch, local=False )
		return self.perform_rsync( source=self.installPrefix, destination=serverPath )

	def execute_tests(self):
		# Prepare
		buildDirectory = self.build_directory()
		runtimeEnv = self.generate_environment(True)
		junitFilename = os.path.join( buildDirectory, 'JUnitTestResults.xml' )

		# Determine if we have tests to run....
		command = self.config.get('Test', 'ctestCountTestsCommand')
		process = subprocess.Popen( shlex.split(command), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=runtimeEnv, cwd=buildDirectory)
		stdout, stderr = process.communicate()
		# Is it necessary to run tests? (tests must be enabled per configuration and CTest must report more than 1 test)
		if not self.config.getboolean('Test', 'testsEnabled') or re.search('Total Tests: 0', stdout, re.MULTILINE):
			# Copy in the skeleton file to keep Jenkins happy
			unitTestSkeleton = os.path.join( self.config.get('General', 'scriptsLocation'), 'templates', 'JUnitTestResults-Success.xml' )
			shutil.copyfile( unitTestSkeleton, junitFilename )
			# All done
			return

		# Setup Xvfb
		runtimeEnv['DISPLAY'] = self.config.get('Test', 'xvfbDisplayName')
		command = self.config.get('Test', 'xvfbCommand')
		xvfbProcess = subprocess.Popen( shlex.split(command), stdout=open(os.devnull, 'w'), stderr=subprocess.STDOUT, env=runtimeEnv )

		# Startup D-Bus and ensure the environment is adjusted
		command = self.config.get('Test', 'dbusLaunchCommand')
		process = subprocess.Popen( shlex.split(command), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=runtimeEnv )
		process.wait()
		for variable in process.stdout:
			 splitVars = variable.split('=', 1)
			 runtimeEnv[ splitVars[0] ] = splitVars[1].strip()

		# Rebuild the Sycoca
		command = self.config.get('Test', 'kbuildsycocaCommand')
		try:
			process = subprocess.Popen( shlex.split(command), stdout=open(os.devnull, 'w'), stderr=subprocess.STDOUT, env=runtimeEnv )
			process.wait()
		except OSError:
			pass

		# Fire-up kdeinit and nepomuk
		kdeinitCommand = self.config.get('Test', 'kdeinitCommand')
		nepomukCommand = self.config.get('Test', 'nepomukCommand')
		try:
			subprocess.Popen( shlex.split(kdeinitCommand), stdout=open(os.devnull, 'w'), stderr=subprocess.STDOUT, env=runtimeEnv )
			subprocess.Popen( shlex.split(nepomukCommand), stdout=open(os.devnull, 'w'), stderr=subprocess.STDOUT, env=runtimeEnv )
		except OSError:
			pass

		# Sleep for a little while, to let kdeinit / nepomuk complete their startup processes
		time.sleep( self.config.getint('Test', 'kdeStartupWait') )

		# Execute CTest
		command = self.config.get('Test', 'ctestRunCommand')
		ctestProcess = subprocess.Popen( shlex.split(command), stdout=sys.stdout, stderr=sys.stderr, cwd=buildDirectory, env=runtimeEnv )

		# Determine the maximum amount of time we will permit CTest to run for
		# To accomodate for possible inconsistencies, we allow an extra 2 lots of the permissible time per test
		testsFound = re.search('Total Tests: ([0-9]+)', stdout, re.MULTILINE).group(1)
		permittedTime = ( int(testsFound) + 2 ) * self.config.getint('Test', 'testTimePermitted')
		# Start timing it
		timeRunning = 0
		while timeRunning < permittedTime and ctestProcess.poll() is None:
			time.sleep(1)
			timeRunning += 1

		# Is it still running? 
		if ctestProcess.returncode is None:
			# Kill it
			ctestProcess.kill()
			# Copy in the failure skeleton file to keep Jenkins happy
			unitTestSkeleton = os.path.join( self.config.get('General', 'scriptsLocation'), 'templates', 'JUnitTestResults-Failure.xml' )
			shutil.copyfile( unitTestSkeleton, junitFilename )
			# Report our failure - overruns are not permitted
			return

		# Transform the CTest output into JUnit output
		junitOutput = self.convert_ctest_to_junit( buildDirectory )
		with open(junitFilename, 'w') as junitFile:
			junitFile.write( str(junitOutput) )

		# All finished, shut everyone down
		command = self.config.get('Test', 'terminateTestEnvCommand')
		subprocess.Popen( shlex.split(command) )
		xvfbProcess.terminate()

	def convert_ctest_to_junit(self, buildDirectory):
		# Where is the base prefix for all test data for this project located?
		testDataDirectory = os.path.join( buildDirectory, 'Testing' )

		# Determine where we will find the test run data for the latest run
		filename = os.path.join( testDataDirectory, 'TAG' )
		with open(filename, 'r') as tagFile:
			testDirectoryName = tagFile.readline().strip()

		# Open the test result XML and load it
		filename = os.path.join( testDataDirectory, testDirectoryName, 'Test.xml' )
		with open(filename , 'r') as xmlFile:
			xmlDocument = etree.parse( xmlFile )

		# Load the XSLT file
		filename = os.path.join( self.config.get('General', 'scriptsLocation'), 'templates', 'ctesttojunit.xsl' )
		with open(filename, 'r') as xslFile:
			xslContent = xslFile.read()
			xsltRoot = etree.XML(xslContent)

		# Transform the CTest XML into JUnit XML
		transform = etree.XSLT(xsltRoot)
		return transform(xmlDocument)

	def execute_cppcheck(self):
		# Prepare to do the cppcheck run
		cpuCount = multiprocessing.cpu_count()
		buildDirectory = self.build_directory()
		runtimeEnv = self.generate_environment(True)
		cppcheckFilename = os.path.join( self.build_directory(), 'cppcheck.xml' )

		# Are we able to run cppcheck?
		if not self.config.getboolean('QualityCheck', 'runCppcheck') or self.projectSources == buildDirectory:
			# Add a empty template
			cppcheckSkeleton = os.path.join( self.config.get('General', 'scriptsLocation'), 'templates', 'cppcheck-empty.xml' )
			shutil.copyfile( cppcheckSkeleton, cppcheckFilename )
			return

		# Prepare the command
		command = self.config.get('QualityCheck', 'cppcheckCommand')
		command = command.format( cpuCount=cpuCount, sources=self.projectSources, buildDirectory=buildDirectory )
		command = shlex.split(command)

		# Run cppcheck and wait for it to finish
		with open(cppcheckFilename, 'w') as cppcheckXml:
			process = subprocess.Popen( command, stdout=sys.stdout, stderr=cppcheckXml, cwd=self.projectSources, env=runtimeEnv )
			process.wait()

	def generate_lcov_data_in_cobertura_format(self):
		# Prepare to execute gcovr
		coberturaFile = os.path.join( self.build_directory(), 'CoberturaLcovResults.xml' )
		command = self.config.get('QualityCheck', 'gcovrCommand')
		command = command.format( sources=self.projectSources )
		command = shlex.split(command)

		# Run gcovr to gather up the lcov data and present it in Cobertura format
		with open(coberturaFile, 'w') as coberturaXml:
			process = subprocess.Popen( command, stdout=coberturaXml, stderr=sys.stderr, cwd=self.projectSources )
			process.wait()

class BulkBuildManager(object):
	# Initialize ourselves
	def __init__(self, projectsFile, sourceRoot, platform):
		# Prepare to determine the projects we will be building
		self.projectManagers = []
		dataFile = open(projectsFile, 'r')

		# Grab the project instance for each and create a manager for it
		for line in dataFile:
			# Make sure we have a project / branch to work with
			buildMatch = re.match("(?P<project>[^:]+):\s*(?P<branch>[^:]+):?\s*(?P<systemBase>.+)", line)
			if not buildMatch:
				continue

			# Retrieve the project / branch to work with
			projectName = buildMatch.group('project').lower()
			branch = buildMatch.group('branch')
			systemBase = buildMatch.group('systemBase')

			# Get the project - and if we don't know it, ignore and continue
			project = ProjectManager.lookup( projectName )
			if not project:
				continue

			# Make sure we have a sources directory
			projectSources = os.path.join( sourceRoot, project.identifier )
			if not os.path.exists( projectSources ):
				os.makedirs( projectSources )

			# Generate a configuration
			config = load_project_configuration( project.identifier, systemBase, platform )

			# Create the manager
			manager = BuildManager(project, branch, projectSources, config)
			self.projectManagers.append(manager)

	def sync_dependencies(self):
		# It is more efficient to ask each project to sync it's own dependencies
		for manager in self.projectManagers:
			# Notify that we are syncing dependencies for this project
			print "\n==== Syncing Dependencies for %s\n" % manager.project.identifier
			# Configure it, and ignore failure
			manager.sync_dependencies()

	def prepare_sources(self):
		# Ask each manager to prepare the sources for a build
		for manager in self.projectManagers:
			# Mention the project being worked on
			print "\n==== Preparing Sources for %s\n" % manager.project.identifier
			# Checkout sources
			manager.checkout_sources( doCheckout = True )
			# Cleanup the sources
			manager.cleanup_sources()
			# Apply any patches
			manager.apply_patches()

	def configure_builds(self):
		# Simply iterate over each manager and ask it to configure it's project
		for manager in self.projectManagers:
			# Notify that we are configuring this project
			print "\n==== Configuring %s\n" % manager.project.identifier
			# Configure it, and ignore failure
			manager.configure_build()

	def compile_builds(self):
		# Simply iterate over each manager and ask it to compile it's project
		for manager in self.projectManagers:
			# Notify that we are configuring this project
			print "\n==== Compiling %s\n" % manager.project.identifier
			# Compile it, and ignore failure
			manager.compile_build()

# Loads a configuration for a given project
def load_project_configuration( project, systemBase = None, platform = None, variation = None ):
	# Create a configuration parser
	config = ConfigParser.SafeConfigParser( {'systemBase': systemBase} )
	# List of prospective files to parse
	configFiles =  ['config/build/global.cfg', 'config/build/{base}.cfg', 'config/build/{host}.cfg', 'config/build/{platform}.cfg']
	configFiles += ['config/build/{project}/project.cfg', 'config/build/{project}/{base}.cfg', 'config/build/{project}/{host}.cfg']
	configFiles += ['config/build/{project}/{platform}.cfg', 'config/build/{project}/{variation}.cfg']
	# Go over the list and load in what we can
	for confFile in configFiles:
		confFile = confFile.format( host=socket.gethostname(), base=systemBase, platform=platform, project=project, variation=variation )
		config.read( confFile )
	# All done, return the configuration
	return config

# Loads the projects
def load_projects( projectFile, projectFileUrl, configDirectory ):
	# Download the list of projects if necessary
	if not os.path.exists(projectFile) or time.time() > os.path.getmtime(projectFile) + 60*60:
		urllib.urlretrieve(projectFileUrl, projectFile)

	# Now load the list of projects into the project manager
	with open(projectFile, 'r') as fileHandle:
		ProjectManager.load_projects( etree.parse(fileHandle) )

	# Load special projects
	for dirname, dirnames, filenames in os.walk( configDirectory ):
		for filename in filenames:
			filePath = os.path.join( dirname, filename )
			ProjectManager.load_extra_project( filePath )

# Load dependencies
def load_project_dependencies( possibleBases, baseDepDirectory, globalDepDirectory ):
	# Load all base specific dependencies
	for base in possibleBases:
		with open( baseDepDirectory + base, 'r' ) as fileHandle:
			ProjectManager.setup_dependencies( fileHandle, systemBase = base )

	# Load the local list of ignored projects
	with open( baseDepDirectory + 'ignore', 'r' ) as fileHandle:
		ProjectManager.setup_ignored( fileHandle )

	# Load the global list of ignored projects
	with open( globalDepDirectory + 'build-script-ignore', 'r' ) as fileHandle:
		ProjectManager.setup_ignored( fileHandle )

	# Load the dependencies
	with open( globalDepDirectory + 'dependency-data', 'r' ) as fileHandle:
		ProjectManager.setup_dependencies( fileHandle )

# Checks for a Jenkins environment, and sets up a argparse.Namespace appropriately if found
def check_jenkins_environment():
	# Prepare
	arguments = argparse.Namespace()

	# Do we have a job name?
	if 'JOB_NAME' in os.environ:
		# Split it out
		jobMatch = re.match("(?P<project>[^_]+)_?(?P<branch>[^_]+)?_?(?P<base>[^_]+)?", os.environ['JOB_NAME'])
		# Now transfer in any non-None attributes
		for name, value in jobMatch.groupdict().iteritems():
			if value is not None:
				setattr(arguments, name, value.lower())

	# Do we have a workspace?
	if 'WORKSPACE' in os.environ:
		# Transfer it
		arguments.sources = os.environ['WORKSPACE']

	# Do we have a build variation?
	if 'Variation' in os.environ:
		# We need this to determine our specific build variation
		arguments.variation = os.environ['Variation']

	# Do we need to change into the proper working directory?
	if 'JENKINS_SLAVE_HOME' in os.environ:
		# Change working directory
		os.chdir( os.environ['JENKINS_SLAVE_HOME'] )

	return arguments
