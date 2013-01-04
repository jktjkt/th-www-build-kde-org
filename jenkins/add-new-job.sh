#!/bin/bash


if [ ! -f jenkins-private.key ]; then
	echo "Missing 'jenkins-private.key' file"
	exit 1
fi

rm jenkins-cli.jar
wget http://build.kde.org/jnlpJars/jenkins-cli.jar || exit 1

for f in $@; do
	FILE=`basename $f`
	PROJECT_BRANCH=${FILE%.xml}
	echo "Adding $PROJECT_BRANCH"

	java -jar jenkins-cli.jar -i jenkins-private.key -s http://build.kde.org/ create-job ${PROJECT_BRANCH} < $f
	sleep 1
done
