#!/bin/bash

. /etc/opt/jfrog/artifactory/default
echo "Max number of open files: `ulimit -n`"
echo "Using ARTIFACTORY_HOME: $ARTIFACTORY_HOME"
echo "Using ARTIFACTORY_PID: $ARTIFACTORY_PID"
export CATALINA_OPTS="$CATALINA_OPTS $JAVA_OPTIONS -Dartifactory.home=$ARTIFACTORY_HOME"
export CATALINA_PID=$ARTIFACTORY_PID
export CATALINA_HOME="$TOMCAT_HOME"
