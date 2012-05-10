#!/usr/bin/env python
# coding: utf-8

import sys,io,os
from string import Template
import xml.dom.minidom
import urllib
import pprint

#KDE_PROJECTS_URL="http://projects.kde.org/kde_projects.xml"
KDE_PROJECTS_URL="kde_projects.xml"
CONFIG_ROOT="jobs"

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
	
	for repo in repos:
		name=None
		repourl=None
		cloneurl=None
		description=None
		path=None
		weburl=None
		branch=None
		identifier=repo.parentNode.getAttribute('identifier')
		for node in repo.childNodes:
			if node.nodeType != xml.dom.Node.ELEMENT_NODE:
				continue
			try:
				if node.tagName == 'web' and node.getAttribute('type') == 'projects':
					repourl = node.childNodes[0].nodeValue
				elif node.tagName == 'url' and node.getAttribute('protocol') == 'git':
					cloneurl = node.childNodes[0].nodeValue
				elif node.tagName == 'branch' and node.getAttribute('i18n') == 'trunk':
					masterBranch = node.childNodes[0].nodeValue
				elif node.tagName == 'branch' and node.getAttribute('i18n') == 'stable':
					stableBranch = node.childNodes[0].nodeValue
			except IndexError:
				continue

		for node in repo.parentNode.childNodes:
			if node.nodeType != xml.dom.Node.ELEMENT_NODE:
				continue
			try:
				if node.tagName == 'name':
					name = node.childNodes[0].nodeValue
				elif node.tagName == 'description':
					description = node.childNodes[1].nodeValue
				elif node.tagName == 'path':
					path = node.childNodes[0].nodeValue
				elif node.tagName == 'web':
					weburl = node.childNodes[0].nodeValue
			except IndexError:
				continue

		if path.startswith( filterPath ):
			if masterBranch is None:
				masterBranch = "master"

			template = Template( templateContent )
			config = template.substitute( name=name, repourl=repourl, cloneurl=cloneurl, description=description, path=path, weburl=weburl, branch=masterBranch, identifier=identifier )
			configFile = open( "%s/%s_master.xml"%(CONFIG_ROOT, path.replace('/', '-')), 'w' )
			configFile.write(config)
			configFile.close

			if stableBranch is not None:
				config = template.substitute( name=name, repourl=repourl, cloneurl=cloneurl, description=description, path=path, weburl=weburl, branch=stableBranch, identifier=identifier )
				configFile = open( "%s/%s_stable.xml"%(CONFIG_ROOT, path.replace('/', '-')), 'w' )
				configFile.write(config)
				configFile.close
			



		