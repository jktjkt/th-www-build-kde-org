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
		print "=> Adding %s:%s as a dependency for %s:%s"%(project.name, branch, self.name, dependent_branch)

	def add_multi_dependencies( self, dependencies ):
		for branch in dependencies:
			if branch in self.dependencies:
				for dependency in dependencies[branch]:
					if dependency in self.dependencies[branch] and  self.dependencies[branch][dependency] != '-':
						if dependencies[branch][dependency] == '-':
							print "=> Removing %s as a dependency from %s:%s"%(dependency, self.name, branch)
							del self.dependencies[branch][dependency]
					elif dependency != self.name:
						print "=> Adding %s:%s as a dependency for %s:%s"%(dependency, dependencies[branch][dependency], self.name, branch)
						self.dependencies[branch][dependency] = dependencies[branch][dependency]
			else:
				self.dependencies[branch] = dependencies[branch]

	def ignore_dependency( self, project, branch = '*' ):
		if not branch in self.dependencies:
			self.dependencies[ branch ] = {}
		if branch is None or branch == '':
			branch = '*'
		self.dependencies[branch][project.name] = '-'
		print "=> Ignoring %s as a dependency for %s:%s"%(project.name, self.name, branch)

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
		return self.name.startswith( path )

	def __str__(self):
		return "%s %s"%(self.name, self.dependencies.keys())


class Dependency_parser(object):
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
	self.projects = {}
	self.multi_dependencies = {}

	def __init__(self, dependency_file = '/code/kde/src/kde-build-metadata/dependency-data', ignore_file = '/code/kde/src/kde-build-metadata/build-script-ignore' ):
		self.ignore_file = ignore_file
		self.dependency_file = dependency_file

	def parse(self):

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

			if not project in projects:
				projects[ project ] = Project( project )
			if not dependency in projects:
				projects[ dependency ] = Project( dependency )

			if match.group('ignore_dependency'):
				projects[project].ignore_dependency( projects[dependency], project_branch )
			else:
				if project[-1] == '*':
					if not project in multi_dependencies:
						multi_dependencies[ project ] = projects[ project ]
					multi_dependencies[project].add_dependency( projects[dependency], project_branch, dependency_branch )
				else:
					projects[project].add_dependency( projects[dependency], project_branch, dependency_branch )

	def add_multi_dependencies(self):
		print "=> Processing multi project dependencies..."
		for multi_dependency in multi_dependencies:
			for project in projects.values():
				if project.is_under_path( multi_dependency ):
					projects[project.name].add_multi_dependencies(projects[multi_dependency].dependencies)
		return projects

	def add_missing_dependencies(self, all_dependent_projects, project):
		dependent_projects = projects[ project ].get_dependencies_for_branch( branch )
		all_dependent_projects.update( dependent_projects )
		for dependent_project in dependent_projects:
			if dependent_project not in all_dependent_projects:
				self.add_missing_dependencies(all_dependent_projects, dependent_project)

	def find_deps_for_project_and_branch(self, project, branch):
		print "Finding dependencies for %s:%s"%(project, branch)

		if project in projects:
			all_dependent_projects = projects[ project ].get_dependencies_for_branch( branch )
			dependent_projects = copy.copy(all_dependent_projects)
			for project in dependent_projects:
				self.add_missing_dependencies(all_dependent_projects, project)
			return all_dependent_projects
		else:
			

if __name__ in '__main__':
	if len(sys.argv) < 3:
		print "Usage: %s <project> <branch>"%sys.argv[0]
		sys.exit(1)

	project = sys.argv[1]
	branch = sys.argv[2]

	# 1: Find all dependencies
	jenkins_slave_home = os.getenv('JENKINS_SLAVE_HOME')
	dep_parser = Dependency_parser(dependency_file = jenkins_slave_home + '/dependencies/dependency-data', ignore_file = jenkins_slave_home + '/dependencies/build-script-ignore' )
	dep_parser.parse()
	if not project in dep_parser.projects:
		dep_parser.projects[project] = Project( project )
	projects = dep_parser.add_multi_dependencies()

	dependencies = dep_parser.find_deps_for_project_and_branch(project, branch)

	# 2: Add dependencies to environment
	build_dir = os.getenv("WORKSPACE")
	f = open( os.path.join( build_dir, "environment-vars.sh" ), 'w' )
	f.write( "#!/bin/bash -x\n" )
	#f.write( "export MASTER=%s\n"%master )
	#f.write( "export ROOT=%s\n"%root )
	f.write( 'export DEPS="' )

	for dependency in dependencies:
		f.write("%s=%s "%(dependency, dependencies[dependency]))
		print "%s:%s"%(dependency, dependencies[dependency])

	f.write( '"' )
	f.close()
