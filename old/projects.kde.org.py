#!/usr/bin/env python
# coding: utf-8

import sys,io,os,time
import re
from string import Template
import xml.dom.minidom
import urllib
import pprint
import codecs
import pprint

KDE_PROJECTS_URL="http://projects.kde.org/kde_projects.xml"
CONFIG_ROOT="jobs"
JENKINS_INSTANCE="http://sandbox.build.kde.org"

def saveConfig(templateContent, values):
	fileName = "%s/%s_%s.xml"%(CONFIG_ROOT, values['identifier'].replace('/', '-'), values['branchType'])
	template = Template( templateContent )
	config = template.substitute( name=values['name'], repourl=values['repourl'], cloneurl=values['cloneurl'], description=values['description'], path=values['path'], weburl=values['weburl'], branch=values['masterBranch'], identifier=values['identifier'] )
	configFile = codecs.open( fileName, 'w', 'utf-8' )
	configFile.write(config)
	configFile.close

def createJobs(dom, templateFile, filterPath):
	print "Creating jobs matching '%s'"%filterPath
	pathFilter = re.compile(filterPath)
	try:
		os.makedirs( CONFIG_ROOT )
	except OSError:
		pass

	templateFile = open(templateFile)

	templateContent = templateFile.read()
	templateFile.close()

	repos = dom.getElementsByTagName('repo')

	scriptFile = open( 'send_configs_to_jenkins.sh', 'w' )
	scriptFile.write( "#!/bin/bash\n\n" )
	scriptFile.write( "if [[ -z ${JENKINS_USER} ]] || [[ -z ${JENKINS_PASSWORD} ]]; then\n" )
	scriptFile.write( "	echo 'JENKINS_USER and JENKINS_PASSWORD must be set'\n" )
	scriptFile.write( "	exit 1\n" )
	scriptFile.write( "fi\n\n" )
	scriptFile.write( "rm jenkins-cli.jar\n" )
	scriptFile.write( "wget %s/jnlpJars/jenkins-cli.jar\n\n"%JENKINS_INSTANCE )

	for repo in repos:
		values = {}
		values['identifier']=repo.parentNode.getAttribute('identifier')
		for node in repo.childNodes:
			if node.nodeType != xml.dom.Node.ELEMENT_NODE:
				continue
			try:
				if node.tagName == 'web' and node.getAttribute('type') == 'projects':
					values['repourl'] = node.childNodes[0].nodeValue
				elif node.tagName == 'url' and node.getAttribute('protocol') == 'git':
					values['cloneurl'] = node.childNodes[0].nodeValue
				elif node.tagName == 'branch' and node.getAttribute('i18n') == 'trunk':
					values['masterBranch'] = node.childNodes[0].nodeValue
				elif node.tagName == 'branch' and node.getAttribute('i18n') == 'stable':
					values['stableBranch'] = node.childNodes[0].nodeValue
			except IndexError:
				continue

		for node in repo.parentNode.childNodes:
			if node.nodeType != xml.dom.Node.ELEMENT_NODE:
				continue
			try:
				if node.tagName == 'name':
					values['name'] = node.childNodes[0].nodeValue
				elif node.tagName == 'description':
					values['description'] = node.childNodes[1].nodeValue
				elif node.tagName == 'path':
					values['path'] = node.childNodes[0].nodeValue
				elif node.tagName == 'web':
					values['weburl'] = node.childNodes[0].nodeValue
			except IndexError:
				continue

		if pathFilter.match(values['path']) is not None:
			print "Exporting '%s'"%values['path']
			if not 'masterBranch' in values:
				values['masterBranch'] = "master"

			values['branchType'] = 'master'
			saveConfig(templateContent, values)

			viewName = values['path'][:values['path'].find('/')]
			if viewName == 'kde':
				viewName = values['path'][4:values['path'].find('/', 4)]

			scriptFile.write( "echo -n %s:%s...\n"%(values['identifier'], values['branchType'] ) )
			scriptFile.write( "java -jar jenkins-cli.jar -s %s -i jenkins-private.key create-job %s_%s <%s"%(JENKINS_INSTANCE, values['identifier'].replace('/', '-'), values['branchType'], "%s/%s_%s.xml\n"%(CONFIG_ROOT, values['identifier'], values['branchType'])) )
			scriptFile.write( "if [[ $? -ne 0 ]]; then\n" )
			scriptFile.write( "    java -jar jenkins-cli.jar -s %s -i jenkins-private.key update-job %s_%s <%s"%(JENKINS_INSTANCE, values['identifier'].replace('/', '-'), values['branchType'], "%s/%s_%s.xml\n"%(CONFIG_ROOT, values['identifier'], values['branchType'])) )
			scriptFile.write( "fi\n" )
			scriptFile.write( "wget --auth-no-challenge --http-user=${JENKINS_USER} --http-password=${JENKINS_PASSWORD} --post-data='name=%s_%s' %s/view/%s/addJobToView\n"%(values['identifier'], values['branchType'], JENKINS_INSTANCE, viewName) )
			scriptFile.write( "echo Done\n" )
			scriptFile.write( "sleep 1\n" )

			if 'stableBranch' in values:
				values['branchType'] = 'stable'
				saveConfig(templateContent, values)
				scriptFile.write( "echo -n %s:%s...\n"%(values['identifier'], values['branchType'] ) )
				scriptFile.write( "java -jar jenkins-cli.jar -s %s -i jenkins-private.key create-job %s_%s <%s"%(JENKINS_INSTANCE, values['identifier'].replace('/', '-'), values['branchType'], "%s/%s_%s.xml\n"%(CONFIG_ROOT, values['identifier'], values['branchType'])) )
				scriptFile.write( "if [[ $? -ne 0 ]]; then\n" )
				scriptFile.write( "    java -jar jenkins-cli.jar -s %s -i jenkins-private.key update-job %s_%s <%s"%(JENKINS_INSTANCE, values['identifier'].replace('/', '-'), values['branchType'], "%s/%s_%s.xml\n"%(CONFIG_ROOT, values['identifier'], values['branchType'])) )
				scriptFile.write( "fi\n" )
				scriptFile.write( "wget --auth-no-challenge --http-user=${JENKINS_USER} --http-password=${JENKINS_PASSWORD} --post-data='name=%s_%s' %s/view/%s/addJobToView\n"%(values['identifier'], values['branchType'], JENKINS_INSTANCE, viewName) )
				scriptFile.write( "echo Done\n" )
				scriptFile.write( "sleep 1\n" )

	scriptFile.close()

def resolveBranch(dom, project, branch):
	repos = dom.getElementsByTagName('repo')

	if branch == 'master':
		branch = 'trunk'
	
	if branch == 'frameworks':
		print branch
		return

	branches=[]
	for repo in repos:
		if repo.parentNode.getAttribute('identifier') == project:
			for node in repo.childNodes:
				if node.nodeType != xml.dom.Node.ELEMENT_NODE:
					continue
				try:
					if node.tagName == 'branch':
						branches.append(node.childNodes[0].nodeValue)
						if node.getAttribute('i18n') == branch:
							print node.childNodes[0].nodeValue
							return
				except IndexError:
					continue
	if branch in branches:
		print branch
		return

	print "master"

def resolvePath(dom, project):
	repos = dom.getElementsByTagName('repo')

	for repo in repos:
		if repo.parentNode.getAttribute('identifier') == project:
			for node in repo.parentNode.childNodes:
				if node.nodeType != xml.dom.Node.ELEMENT_NODE:
					continue
				if node.tagName == 'path':
					print node.childNodes[0].nodeValue
					return
	return

def resolveRepo(dom, project):
	repos = dom.getElementsByTagName('repo')

	for repo in repos:
		if repo.parentNode.getAttribute('identifier') == project:
			for node in repo.childNodes:
				if node.nodeType != xml.dom.Node.ELEMENT_NODE:
					continue
				if node.tagName == 'url' and node.getAttribute('protocol') == 'git':
					print node.childNodes[0].nodeValue
					return
	return

def resolveIdentifier(dom, path):
	repos = dom.getElementsByTagName('repo')

	for repo in repos:
		for node in repo.parentNode.childNodes:
			if node.nodeType != xml.dom.Node.ELEMENT_NODE:
				continue
			if node.tagName == 'path' and node.childNodes[0].nodeValue == path:
				print repo.parentNode.getAttribute('identifier')
				return
	return

if __name__ in "__main__":

	usage = "Usage: %s [resolve identifier <project_path>] [resolve path <project>] [resolve branch <project> <branch>] [createjobs <template-file> [filter_path]]"%sys.argv[0]

	project_file = "./project_file.xml"

	if len(sys.argv) < 3:
		print usage
		sys.exit(1)

	if not os.path.exists(project_file):
		sys.stderr.write("=> Retrieving project listing from %s\n"%KDE_PROJECTS_URL)
		urllib.urlretrieve(KDE_PROJECTS_URL, project_file)
	elif time.time() > os.path.getmtime(project_file) + 60*60:
		sys.stderr.write("=> Refreshing project listing from %s (%i s old)\n"%(KDE_PROJECTS_URL, time.time() - os.path.getmtime(project_file)))
		urllib.urlretrieve(KDE_PROJECTS_URL, project_file)

	dom = xml.dom.minidom.parse(project_file)

	if len(dom.getElementsByTagName('repo')) == 0:
		sys.stderr.write("=> No projects found in project listing, check if %s returns a vaild xml file\n"%KDE_PROJECTS_URL)
		sys.exit(1)

	if sys.argv[1] == 'resolve':
		project = sys.argv[3].lower()
		if sys.argv[2] == 'branch' and len(sys.argv) == 5:
			branch = sys.argv[4]
			resolveBranch(dom, project, branch)
		elif sys.argv[2] == 'path' and len(sys.argv) == 4:
			resolvePath(dom, project)
		elif sys.argv[2] == 'repo' and len(sys.argv) == 4:
			resolveRepo(dom, project)
		elif sys.argv[2] == 'identifier' and len(sys.argv) == 4:
			resolveIdentifier(dom, project)
		else:
			print usage
			sys.exit(1)
	elif sys.argv[1] == 'createjobs' and len(sys.argv) <= 4:
		templateFile = sys.argv[2]
		if len(sys.argv) == 4:
			filterPath = sys.argv[3]
		else:
			filterPath = ""
		createJobs(dom, templateFile, filterPath)
	else:
		print usage
		sys.exit(1)






