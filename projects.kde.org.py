#!/usr/bin/env python
# coding: utf-8

import sys,io,os,time
from string import Template
import xml.dom.minidom
import urllib
import pprint
import codecs

KDE_PROJECTS_URL="http://projects.kde.org/kde_projects.xml"
CONFIG_ROOT="jobs"
JENKINS_INSTANCE="http://build.kde.org"

def saveConfig(values):
	fileName = "%s/%s_%s.xml"%(CONFIG_ROOT, values['identifier'].replace('/', '-'), values['branchType'])
	config = template.substitute( name=values['name'], repourl=values['repourl'], cloneurl=values['cloneurl'], description=values['description'], path=values['path'], weburl=values['weburl'], branch=values['masterBranch'], identifier=values['identifier'] )
	configFile = codecs.open( fileName, 'w', 'utf-8' )
	configFile.write(config)
	configFile.close

def createJobs(dom, templateFile, filterPath):
	try:
		os.makedirs( CONFIG_ROOT )
	except OSError:
		pass

	templateFile = open(templateFile)

	templateContent = templateFile.read()
	templateFile.close()

	repos = dom.getElementsByTagName('repo')

	scriptFile = open( 'send_configs_to_jenkins.sh', 'w' )
	scriptFile.write( "#!/bin/bash -e\n\n" )
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

		if values['path'].startswith( filterPath ):
			if not 'masterBranch' in values:
				values['masterBranch'] = "master"

			template = Template( templateContent )
			values['branchType'] = 'master'
			saveConfig(values)
			scriptFile.write( "echo -n %s:%s...\n"%(values['identifier'], values['branchType'] ) )
			scriptFile.write( "java -jar jenkins-cli.jar -s %s -i jenkins-private.key create-job %s_%s <%s"%(JENKINS_INSTANCE, values['identifier'].replace('/', '-'), values['branchType'], "%s/%s_%s.xml\n"%(CONFIG_ROOT, values['path'].replace('/', '-'), values['branchType'])) )
			scriptFile.write( "echo Done\n" )
			scriptFile.write( "sleep 1\n" )

			if 'stableBranch' in values:
				values['branchType'] = 'stable'
				saveConfig(values)
				scriptFile.write( "echo -n %s:%s...\n"%(values['identifier'], values['branchType'] ) )
				scriptFile.write( "java -jar jenkins-cli.jar -s %s -i jenkins-private.key create-job %s_%s <%s"%(JENKINS_INSTANCE, values['identifier'].replace('/', '-'), values['branchType'], "%s/%s_%s.xml\n"%(CONFIG_ROOT, values['path'].replace('/', '-'), values['branchType'])) )
				scriptFile.write( "echo Done\n" )
				scriptFile.write( "sleep 1\n" )

	scriptFile.close()

def resolveBranch(dom, project, branch):
	repos = dom.getElementsByTagName('repo')

	if branch == 'master':
		branch == 'trunk'

	realBranch = ""

	for repo in repos:
		if repo.parentNode.getAttribute('identifier') == project:
			for node in repo.childNodes:
				if node.nodeType != xml.dom.Node.ELEMENT_NODE:
					continue
				try:
					if node.tagName == 'branch' and node.getAttribute('i18n') == branch:
						realBranch = node.childNodes[0].nodeValue
				except IndexError:
					continue
	print realBranch

if __name__ in "__main__":
	usage = "Usage: %s [resolve <project> <branch>] [createjobs <template-file> [filter_path]]"%sys.argv[0]
	if len(sys.argv) < 4:
		print usage
		sys.exit(1)
	elif sys.argv[1] == 'resolve':
		if len(sys.argv) != 4:
			print usage
			sys.exit(1)
	elif sys.argv[1] == 'createjobs':
		if len(sys.argv) < 3 or len(sys.argv) > 4:
			print usage
			sys.exit(1)
	else:
		print usage
		sys.exit(1)

	project_file = "./project_file.xml"
	if not os.path.exists(project_file) or time.localtime() > os.path.getmtime(project_file) + 60*60:
		urllib.urlretrieve(KDE_PROJECTS_URL, project_file)

	dom = xml.dom.minidom.parse(project_file)

	if sys.argv[1] == 'resolve':
		project = sys.argv[2]
		branch = sys.argv[3]
		resolveBranch(dom, project, branch)
	else:
		templateFile = sys.argv[2]
		if len(sys.argv) == 3:
			filterPath = sys.argv[3]
		else:
			filterPath = ""
		createJobs(dom, templateFile, filterPath)






