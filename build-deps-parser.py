#!/usr/bin/env python
# coding: utf-8
import sys,os
import re
import copy
import pprint

class Project(object):
	def __init__(self, name):
		self.dependencies = {'*' : {}}
		self.name = name

	def add_dependency( self, project, branch = '*', dependent_branch = '*' ):
		if not branch in self.dependencies:
			self.dependencies[ branch ] = {}
		if branch is None or branch == '':
			branch = '*'
		if dependent_branch is None or dependent_branch == '':
			dependent_branch = '*'
		self.dependencies[branch][project.name] = dependent_branch
		print "==> Adding %s:%s as a dependency for %s:%s"%(project.name, branch, self.name, dependent_branch)

	def add_multi_dependencies( self, dependencies ):
		for branch in dependencies:
			if branch in self.dependencies:
				for dependency in dependencies[branch]:
					if dependency in self.dependencies[branch] and  self.dependencies[branch][dependency] != '-':
						if dependencies[branch][dependency] == '-':
							print "==> Removing %s as a dependency from %s:%s"%(dependency, self.name, branch)
							del self.dependencies[branch][dependency]
					elif dependency != self.name:
						print "==> Adding %s:%s as a dependency for %s:%s"%(dependency, dependencies[branch][dependency], self.name, branch)
						self.dependencies[branch][dependency] = dependencies[branch][dependency]
			else:
				self.dependencies[branch] = dependencies[branch]

	def ignore_dependency( self, project, branch = '*' ):
		if not branch in self.dependencies:
			self.dependencies[ branch ] = {}
		if branch is None or branch == '':
			branch = '*'
		self.dependencies[branch][project.name] = '-'
		print "==> Ignoring %s as a dependency for %s:%s"%(project.name, self.name, branch)

	def get_dependencies_for_branch(self, branch):
		dependencies = self.dependencies['*']
		#print "Global deps: ",
		#pprint.pprint( dependencies )
		if branch in self.dependencies and branch != '*':
			#print "Branch deps: ",
			#pprint.pprint( self.dependencies[branch] )
			for dependency_name in self.dependencies[branch]:
				if not dependency_name in dependencies:
					dependencies[dependency_name] = self.dependencies[branch][dependency_name]
				else:
					if self.dependencies[branch][dependency_name] == '-':
						del dependencies[dependency_name]
					else:
						dependencies[dependency_name] = self.dependencies[branch][dependency_name]
		return dependencies

	def is_under_path(self, path):
		if path[-1] == '*':
			path = path[:-1]
		return self.name.startswith( path ) or len(path) == 0

	def __str__(self):
		return "%s %s"%(self.name, self.dependencies.keys())


class Dependency_parser(object):
	__instance = None

	class __impl(object):
		ruleLineRe = re.compile(r"""
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

		def __init__(self, dependency_file, ignore_file):
			self.ignore_file = ignore_file
			self.dependency_file = dependency_file
			self.projects = {}
			self.multi_dependencies = {}
			self.__parse()

		def __parse(self):

			print "Parsing build dependency data"
			ignore_info = open( self.ignore_file )
			lines = ignore_info.readlines()
			ignore_info.close()

			ignored_projects = {}
			for line in lines:
				ignored_projects[line.strip()] = True
				print("=> Ignoring project: " + line.strip())

			dep_info = open( self.dependency_file )
			lines = dep_info.readlines()
			dep_info.close()

			for line in lines:
				line = line.strip()
				commentPos = line.find("#")
				if commentPos >= 0:
					line = line[0:commentPos]
				if len(line) == 0:
					continue

				match = self.ruleLineRe.search( line )
				if not match:
					print("=> Invalid rule:" + line)
					continue

				project = match.group('project')
				dependency = match.group('dependency')
				project_branch = '*'
				dependency_branch = None
				if match.group('project_branch'):
					project_branch = match.group('project_branch')

				if match.group('dependency_branch'):
					dependency_branch = match.group('dependency_branch')

				if not project in self.projects:
					self.projects[ project ] = Project( project )
				if not dependency in self.projects:
					self.projects[ dependency ] = Project( dependency )

				if match.group('ignore_dependency'):
					self.projects[project].ignore_dependency( self.projects[dependency], project_branch )
				else:
					if project[-1] == '*':
						if not project in self.multi_dependencies:
							self.multi_dependencies[ project ] = self.projects[ project ]
						self.multi_dependencies[project].add_dependency( self.projects[dependency], project_branch, dependency_branch )
					else:
						self.projects[project].add_dependency( self.projects[dependency], project_branch, dependency_branch )

		def add_multi_dependencies(self):
			print "=> Processing multi project dependencies..."
			for multi_dependency in self.multi_dependencies:
				for project in self.projects.values():
					if project.is_under_path( multi_dependency ):
						self.projects[project.name].add_multi_dependencies(self.projects[multi_dependency].dependencies)
			return self.projects

		def add_missing_dependencies(self, all_dependent_projects, project, branch):
			dependent_projects = self.projects[ project ].get_dependencies_for_branch( branch )
			all_dependent_projects.update( dependent_projects )
			for dependent_project in dependent_projects:
				if dependent_project not in all_dependent_projects:
					self.add_missing_dependencies(all_dependent_projects, dependent_project)

		def find_deps_for_project_and_branch(self, project, branch):
			print "Finding dependencies for %s:%s"%(project, branch)

			if project in self.projects:
				all_dependent_projects = self.projects[ project ].get_dependencies_for_branch( branch )
				dependent_projects = copy.copy(all_dependent_projects)
				for project in dependent_projects:
					self.add_missing_dependencies(all_dependent_projects, project, branch)
				return all_dependent_projects

		def sort_deps(self, project):
			print "Sorting dependencies for %s"%project


	def __init__(self, dependency_file, ignore_file):
		""" Create singleton instance """
		# Check whether we already have an instance
		if Dependency_parser.__instance is None:
			# Create and remember instance
			Dependency_parser.__instance = Dependency_parser.__impl(dependency_file, ignore_file)

		# Store instance reference as the only member in the handle
		self.__dict__['_Dependency_parser__instance'] = Dependency_parser.__instance

	def __getattr__(self, attr):
		""" Delegate access to implementation """
		return getattr(self.__instance, attr)

	def __setattr__(self, attr, value):
		""" Delegate access to implementation """
		return setattr(self.__instance, attr, value)


def calculate_single_dependency(project, branch):
	# 1: Find all dependencies
	dependency_file = ''
	ignore_file = ''
	jenkins_slave_home = os.getenv('JENKINS_SLAVE_HOME')
	if jenkins_slave_home is None:
		print "JENKINS_SLAVE_HOME environment variable not set"
		sys.exit(1)
	else:
		dependency_file = jenkins_slave_home + '/dependencies/dependency-data'
		ignore_file = jenkins_slave_home + '/dependencies/build-script-ignore'

	dep_parser = Dependency_parser(dependency_file = dependency_file, ignore_file = ignore_file )
	if not project in dep_parser.projects:
		print project + " was not in dependency file, adding"
		dep_parser.projects[project] = Project( project )
	projects = dep_parser.add_multi_dependencies()

	dependencies = dep_parser.find_deps_for_project_and_branch(project, branch)

	return dependencies

def order_projects(projects):
	print "Finding order of ",
	pprint.pprint(projects)
	ordered_dependencies = []
	project_dependencies = {}
	for project in projects:
		print "=>Adding deps for %s"%project
		project_dependencies[project] = calculate_single_dependency(project, 'master')

	pprint.pprint( project_dependencies )

	for project in projects:
		insert_index = 0
		for dependency in project_dependencies[project].iterkeys():
			if dependency in ordered_dependencies and insert_index <= ordered_dependencies.index(dependency):
				insert_index = ordered_dependencies.index(dependency) + 1
		ordered_dependencies.insert(insert_index, project)
	return ordered_dependencies

if __name__ in '__main__':
	if len(sys.argv) < 3:
		print "Usage: %s <project> <branch>"%sys.argv[0]
		sys.exit(1)

	workspace = os.getenv("WORKSPACE")

	if len(sys.argv) > 3:
		projects = []
		for project in sys.argv[1:]:
			projects.append(project)
		ordered_projects = order_projects(projects)

		f = open( os.path.join( workspace, "build-kde-org.dependency.order" ), 'w' )
		f.write( "#!/bin/bash -x\n" )
		f.write( 'export ORDERED_DEPENDENCIES="' )

		for project in ordered_projects:
			print project, " ",
			f.write("%s "%(project))

		f.write( '"' )
		f.close()
	else:
		project = sys.argv[1]
		branch = sys.argv[2]
		dependencies = calculate_single_dependency(project, branch)

		f = open( os.path.join( workspace, "build-kde-org.dependencies" ), 'w' )
		f.write( "#!/bin/bash -x\n" )
		f.write( 'export DEPS="' )

		for dependency in dependencies:
			f.write("%s=%s "%(dependency, dependencies[dependency]))
			print "%s:%s"%(dependency, dependencies[dependency])

		f.write( '"' )
		f.close()
