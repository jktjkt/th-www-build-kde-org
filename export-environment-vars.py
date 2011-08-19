#!/usr/bin/python
# vim: set sw=4 sts=4 et tw=80 :

"""
{ 
	"kdelibs" : 
		{ "master"  : {"deps" : "master"},
		   "KDE/4.7" : {"deps" : "master"}
		},
	"kdepimlibs" :
		{
			"master"  : {"deps" : "master", "kdelibs" : "KDE/4.7"},
			"4.7"     : {"deps" : "master", "kdelibs" : "KDE/4.7"}
		}
}
"""

import os, sys
import json
import argparse

root=None
master=None

def check_environment():
	if not os.getenv( "WORKSPACE" ):
		print "Missing ${WORKSPACE} environment variable, fatal error!"
		sys.exit( 1 )
	if not os.getenv( "JOB_NAME" ):
		print "Missing ${JOB_NAME} environment variable, fatal error!"
		sys.exit( 1 )
	if not os.getenv( "GIT_BRANCH" ):
		print "Missing ${GIT_BRANCH} environment variable, fatal error!"
		sys.exit( 1 )

def read_build_deps():
	f = open('build-deps.txt', 'r')
	data = f.read()
	f.close()
	module_deps = json.loads(data)
	return module_deps

def get_current_module_str( module_deps ):
	export_str = ""
	for module, branches in module_deps.iteritems():
		print module, "-",
		if os.getenv("JOB_NAME") == module:
			print "Match, creating dependency exports..."
			for branch, branch_deps in branches.iteritems():
				if os.getenv("GIT_BRANCH") == branch:
					print "    ", branch
					export_str = 'export DEPS="'
					for dep, dep_branch in branch_deps.iteritems():
						print "        ", dep, "->", dep_branch
						export_str += "%s=%s "%(dep, dep_branch)
					export_str = export_str.strip() + '"'
					print export_str
		else:
			print "No match"
	return export_str

def write_export_file( export_str ):
	build_dir = os.getenv("WORKSPACE")
	f = open( os.path.join( build_dir, "environment-vars.sh" ), 'w' )
	f.write( export_str + "\n" )
	f.write( "export ROOT=%s\n"%root )
	f.write( "export MASTER=%s\n"%master )
	f.close()

def main():
	check_environment()
	module_deps = read_build_deps()
	export_str = get_current_module_str( module_deps )
	write_export_file( export_str )

def check_args():
	parser = argparse.ArgumentParser( description='Helper for setting variables that are needed in the build steps' )
	parser.add_argument( '-r, --root', dest='root', action='store', required=True, help='Path to where the install root is.' )
	parser.add_argument( '-m, --master', dest='master', action='store', required=True, help='Address of the master build slave, ie where the authoritive copy of all dependencies are stored.' )
	args = parser.parse_args()
	

if __name__ == "__main__":
	check_args()
	main()
