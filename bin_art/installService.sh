#!/bin/bash

#
errorArtHome() {
    echo
    echo -e "\033[31m** ERROR: $1\033[0m"
    echo
    exit 1
}

checkRoot() {
    curUser=
    if [ -x "/usr/xpg4/bin/id" ]
    then
        curUser=`/usr/xpg4/bin/id -nu`
    else
        curUser=`id -nu`
    fi
    if [ "$curUser" != "root" ]
    then
        errorArtHome "Only root user can install artifactory as a service"
    fi

    if [ "$0" = "." ] || [ "$0" = "source" ]; then
        errorArtHome "Cannot execute script with source $0"
    fi
}

getArtUser() {
    if [ -n "$1" ]; then
        ARTIFACTORY_USER=$1
    fi
    if [ -z "$ARTIFACTORY_USER" ]; then
        ARTIFACTORY_USER=artifactory
    fi
}

createArtUser() {
    echo -n "Creating user ${ARTIFACTORY_USER}..."
    artifactoryUsername=`getent passwd ${ARTIFACTORY_USER} | awk -F: '{print $1}'`
    if [ "$artifactoryUsername" = "${ARTIFACTORY_USER}" ]; then
        echo -n "already exists..."
    else
        echo -n "creating..."
        useradd -m -s `which bash` ${ARTIFACTORY_USER}
        if [ ! $? ]; then
            errorArtHome "Could not create user ${ARTIFACTORY_USER}"
        fi
    fi
    echo " DONE"
}

createArtEtc() {
    echo
    echo -n "Checking configuration link and files in $artEtcDir..."
    if [ -L ${ARTIFACTORY_HOME}/etc ]; then
        echo -n "already exists, no change..."
    else
        echo
        echo -n "Moving configuration dir $artExtractDir/etc $artExtractDir/etc.original..."
        mv $artExtractDir/etc $artExtractDir/etc.original || \
            errorArtHome "Could not move $artExtractDir/etc $artExtractDir/etc.original"
        if [ ! -d $artEtcDir ]; then
            mkdir -p $artEtcDir || errorArtHome "Could not create $artEtcDir"
        fi
        echo -n "creating the link and updating dir..."
        ln -s $artEtcDir $ARTIFACTORY_HOME/etc && \
        cp -R $artExtractDir/etc.original/* $artEtcDir && \
        etcOK=true
        [ $etcOK ] || errorArtHome "Could not create $artEtcDir"
    fi
    echo -e " DONE"
}

createArtDefault() {
    echo -n "Creating environment file $artDefaultFile..."
    if [ -e $artDefaultFile ]; then
        echo -n "already exists, no change..."
    else
        # Populating the /etc/opt/jfrog/artifactory/default with ARTIFACTORY_HOME and ARTIFACTORY_USER
        echo -n "creating..."
        cat ${ARTIFACTORY_HOME}/bin/artifactory.default > $artDefaultFile && \
        echo "" >> $artDefaultFile

        sed --in-place -e "
            s,#export ARTIFACTORY_HOME=.*,export ARTIFACTORY_HOME=${ARTIFACTORY_HOME},g;
            s,#export ARTIFACTORY_USER=.*,export ARTIFACTORY_USER=${ARTIFACTORY_USER},g;
            s,export TOMCAT_HOME=.*,export TOMCAT_HOME=${TOMCAT_HOME},g;
            s,export $ARTIFACTORY_PID=.*,export $ARTIFACTORY_PID=${artRunDir}/artifactory.pid,g;" $artDefaultFile || \
                errorArtHome "Could not change values in $artDefaultFile"
    fi
    echo -e " DONE"
    echo -e "\033[33m** INFO: Please edit the files in $artEtcDir to set the correct environment\033[0m"
    echo -e "\033[33mEspecially $artDefaultFile that defines ARTIFACTORY_HOME, JAVA_HOME and JAVA_OPTIONS\033[0m"
}

createArtRun() {
    # Since tomcat 6.0.24 the PID file cannot be created before running catalina.sh. Using /var/opt/jfrog/artifactory/run folder.
    if [ ! -d "$artRunDir" ]; then
        mkdir -p "$artRunDir" || errorArtHome "Could not create $artRunDir"
    fi
}

installService() {
    serviceName=$(basename $artServiceFile)
    serviceFiles=$artBinDir/../misc/service
    if [ -e "$artServiceFile" ]; then
        cp -f $artServiceFile $serviceFiles/$serviceName.init.backup
    fi
    cp -f $serviceFiles/artifactory $artServiceFile
    chmod a+x $artServiceFile

    #change pidfile and default location if needed
    sed --in-place -e "
     /processname:/ s%artifactory%$serviceName%g;
     /Provides:/ s%artifactory%$serviceName%g;
     s%# pidfile: .*%# pidfile: $artRunDir/artifactory.pid%g;
     s%/etc/opt/jfrog/artifactory/default%$artEtcDir/default%g;
     " $artServiceFile || errorArtHome "Could not change values in $artServiceFile"

    # Try update-rc.d for debian/ubuntu else use chkconfig
    if [ -x /usr/sbin/update-rc.d ]; then
        echo
        echo -n "Initializing artifactory service with update-rc.d..."
        update-rc.d $serviceName defaults && \
        chkconfigOK=true
    elif [ -x /usr/sbin/chkconfig ] || [ -x /sbin/chkconfig ]; then
        echo
        echo -n "Initializing $serviceName service with chkconfig..."
        chkconfig --add $serviceName && \
        chkconfig $serviceName on && \
        chkconfig --list $serviceName && \
        chkconfigOK=true
    else
        ln -s $artServiceFile /etc/rc3.d/S99$serviceName && \
        chkconfigOK=true
    fi
    [ $chkconfigOK ] || errorArtHome "Could not install service"
    echo -e " DONE"
}

prepareTomcat() {
    cp $serviceFiles/setenv.sh $TOMCAT_HOME/bin/setenv.sh && \
     sed --in-place -e "
      s%/etc/opt/jfrog/artifactory/default%$artEtcDir/default%g;
      " $TOMCAT_HOME/bin/setenv.sh && \
      chmod a+x $TOMCAT_HOME/bin/* || errorArtHome "Could not set the $TOMCAT_HOME/bin/setenv.sh"

    if [ ! -L "$TOMCAT_HOME/logs" ]; then
        if [ -d $TOMCAT_HOME/logs ]; then
            mv $TOMCAT_HOME/logs $TOMCAT_HOME/logs.original
            mkdir $TOMCAT_HOME/logs
        fi
        mkdir -p $artLogDir/catalina || errorArtHome "Could not create dir $artLogDir/catalina"
        ln -s $artLogDir/catalina $TOMCAT_HOME/logs && \
        chmod -R u+w $TOMCAT_HOME/logs && \
        logOK=true
        [ logOK ] || errorArtHome "Could not create link from $TOMCAT_HOME/logs to $artLogDir/catalina"
    fi
    if [ ! -d $TOMCAT_HOME/temp ];then
        mkdir $TOMCAT_HOME/temp
    fi
    chmod -R u+w ${TOMCAT_HOME}/work
}

setPermissions() {
    echo
    echo -n "Setting file permissions..."
    chown -R -L ${ARTIFACTORY_USER}: ${ARTIFACTORY_HOME} || errorArtHome "Could not set permissions"
    echo -e " DONE"
}

##
checkRoot

artBinDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artExtractDir="$(cd "$(dirname "$artBinDir")" && pwd)"

ARTIFACTORY_HOME="$artExtractDir"
[ -n "$artEtcDir" ] || artEtcDir="/etc/opt/jfrog/artifactory"
TOMCAT_HOME="$ARTIFACTORY_HOME/tomcat"
artLogDir="$ARTIFACTORY_HOME/logs"
artRunDir="$ARTIFACTORY_HOME/run"
[ -n "$artServiceFile" ] || artServiceFile="/etc/init.d/artifactory"
artDefaultFile="$artEtcDir/default"

getArtUser

echo
echo "Installing artifactory as a Unix service that will run as user ${ARTIFACTORY_USER}"
echo "Installing artifactory with home ${ARTIFACTORY_HOME}"

createArtUser "$@"

createArtEtc

createArtDefault

createArtRun

installService

prepareTomcat

setPermissions

echo
echo -e "\033[33m************ SUCCESS ****************\033[0m"
echo -e "\033[33mInstallation of Artifactory completed\033[0m"
echo
echo "Please check $artEtcDir, $TOMCAT_HOME and $ARTIFACTORY_HOME folders"
echo "Please check $artServiceFile startup script"
echo
echo "you can now check installation by running:"
echo "> service artifactory check (or $artServiceFile check)"
echo
echo "Then activate artifactory with:"
echo "> service artifactory start (or $artServiceFile start)"
echo
