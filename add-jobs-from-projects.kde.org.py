#!/usr/bin/env python
# coding: utf-8

import sys,io,os
from string import Template
import xml.dom.minidom
import urllib
import pprint
import codecs

KDE_PROJECTS_URL="http://projects.kde.org/kde_projects.xml"
#KDE_PROJECTS_URL="kde_projects.xml"
CONFIG_ROOT="jobs"
JENKINS_INSTANCE="http://build.kde.org"

def saveConfig(values):
	fileName = "%s/%s_%s.xml"%(CONFIG_ROOT, values['identifier'].replace('/', '-'), values['branchType'])
	config = template.substitute( name=values['name'], repourl=values['repourl'], cloneurl=values['cloneurl'], description=values['description'], path=values['path'], weburl=values['weburl'], branch=values['masterBranch'], identifier=values['identifier'] )
	configFile = codecs.open( fileName, 'w', 'utf-8' )
	configFile.write(config)
	configFile.close

if __name__ in "__main__":

	if len(sys.argv) < 2:
		print "Usage: %s <template-file> [filter_path]"%sys.argv[0]
		sys.exit(1)

	try:
		os.makedirs( CONFIG_ROOT )
	except OSError:
		pass
	templateFile = sys.argv[1]
	templateFile = open(templateFile)

	templateContent = templateFile.read()
	templateFile.close()

	if len(sys.argv) == 3:
		filterPath = sys.argv[2]
	else:
		filterPath = "kde/"

	dom = xml.dom.minidom.parse(urllib.urlopen(KDE_PROJECTS_URL))

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