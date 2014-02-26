# Settings
JENKINS_SLAVE_HOME=$HOME/scripts
JENKINS_BRANCH="production"
JENKINS_DEPENDENCY_BRANCH="master"

# Move to the slave home
if [ ! -d ${JENKINS_SLAVE_HOME} ]; then
	mkdir -p ${JENKINS_SLAVE_HOME}
fi
cd ${JENKINS_SLAVE_HOME}

# Checkout our scripts
if [ ! -d .git ]; then
	git clone git://anongit.kde.org/websites/build-kde-org .
fi
git fetch origin
git checkout ${JENKINS_BRANCH}
git merge --ff-only origin/${JENKINS_BRANCH}

# Setup the dependency data
if [ ! -d ${JENKINS_SLAVE_HOME}/dependencies ]; then
	mkdir -p ${JENKINS_SLAVE_HOME}/dependencies
fi
pushd ${JENKINS_SLAVE_HOME}/dependencies
(
	if [ ! -d ".git" ]; then
		git clone git://anongit.kde.org/kde-build-metadata .
	fi
	git fetch origin
	git checkout ${JENKINS_DEPENDENCY_BRANCH}
	git merge --ff-only origin/${JENKINS_DEPENDENCY_BRANCH}
)
popd

# Setup the ecma262 data (needed for kdelibs)
if [ ! -d ${JENKINS_SLAVE_HOME}/ecma262 ]; then
	mkdir -p ${JENKINS_SLAVE_HOME}/ecma262
fi
pushd ${JENKINS_SLAVE_HOME}/ecma262
(
	if [ ! -d ".hg" ]; then
		hg clone http://hg.ecmascript.org/tests/test262/ .
	fi
	hg pull -u
)
popd

# Setup the poppler test data (needed for poppler)
if [ ! -d ${JENKINS_SLAVE_HOME}/poppler-test-data ]; then
        mkdir -p ${JENKINS_SLAVE_HOME}/poppler-test-data
fi
pushd ${JENKINS_SLAVE_HOME}/poppler-test-data
(
        if [ ! -d ".git" ]; then
                git clone git://git.freedesktop.org/git/poppler/test .
        fi
        git pull
)
popd

# Setup the dependency diagram utilities (needed for dependency data extraction)
if [ ! -d ${JENKINS_SLAVE_HOME}/kapidox ]; then
	mkdir -p ${JENKINS_SLAVE_HOME}/kapidox
fi
pushd ${JENKINS_SLAVE_HOME}/kapidox
(
	if [ ! -d ".git" ]; then
		git clone git://anongit.kde.org/kapidox .
	fi
	git fetch origin
	git checkout wip/standalone-depdiagram-prepare
	git merge --ff-only wip/standalone-depdiagram-prepare
)
popd
