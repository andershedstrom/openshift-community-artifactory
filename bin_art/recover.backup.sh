#!/bin/bash

TIMESTAMP=`echo "$(date '+%T')" | tr -d ":"`
CURRENT_TIME="$(date '+%Y%m%d').$TIMESTAMP"

# Check root user
CURRENT_USER=`id -nu`
if [ "$CURRENT_USER" != "root" ]; then
    echo
    echo "ERROR: This tool can only be used when logged in as root."
    echo
    exit 1
fi

# Check the installation
checkCurrentInstall() {
    ARTIFACTORY_RPM_NAME=`rpm -qa artifactory`

    if [ $ARTIFACTORY_RPM_NAME ]; then
        echo "INFO: $ARTIFACTORY_RPM_NAME found. Checking for FHS or standard layout."
        if [ ! -x "/etc/init.d/artifactory" ]; then
            echo "ERROR: Artifactory RPM $ARTIFACTORY_RPM_NAME installed but init script /etc/init.d/artifactory not executable!"
            exit 1
        fi
        FHS_SCRIPT="`grep "/etc/opt/jfrog/artifactory/default" "/etc/init.d/artifactory"`"
        if [ -n "$FHS_SCRIPT" ]; then
            echo "INFO: Artifactory FHS installed!"
            isFhs=true
            ARTIFACTORY_HOME="/var/opt/jfrog/artifactory"
            ARTIFACTORY_BIN_HOME="/opt/jfrog/artifactory"
            ETC_FOLDER="/etc/opt/jfrog/artifactory"
        else
            echo "INFO: Original Artifactory with no FHS installed!"
            isFhs=false
            ARTIFACTORY_HOME="/var/lib/artifactory"
            ARTIFACTORY_BIN_HOME="/opt/artifactory"
            ETC_FOLDER="/etc/artifactory"
        fi
    else
        echo "ERROR: Artifactory needs to be installed in your system."
        exit 1
    fi
}

# List backups available
listCurrentBackups() {
    NO_FHS_BACKUP_FOLDER="/var/lib"
    OLD_FHS_BACKUP_FOLDER="/var/opt"
    FHS_BACKUP_FOLDER="/var/opt/jfrog"
    NO_FHS_BACKUP_FOLDERS=`'ls' --format=single-column $NO_FHS_BACKUP_FOLDER | grep artifactory.backup`
    OLD_FHS_BACKUP_FOLDERS=`'ls' --format=single-column $OLD_FHS_BACKUP_FOLDER | grep jfrog.artifactory.backup`
    FHS_BACKUP_FOLDERS=`'ls' --format=single-column $FHS_BACKUP_FOLDER | grep artifactory.backup`
    if [ -n "$NO_FHS_BACKUP_FOLDERS" ] || [ -n "$FHS_BACKUP_FOLDERS" ]; then
        echo "INFO: Backups available: "
        echo ""
        C=1
        for i in $NO_FHS_BACKUP_FOLDERS; do
            FILE_LIST[$C]="$NO_FHS_BACKUP_FOLDER/$i"
            echo "$C) ${FILE_LIST[$C]}"
            let C=$C+1
        done
        FHS_NUMBER=$C
        for j in $OLD_FHS_BACKUP_FOLDERS; do
            FILE_LIST[$C]="$OLD_FHS_BACKUP_FOLDER/$j"
            echo "$C) ${FILE_LIST[$C]}"
            let C=$C+1
        done
        for j in $FHS_BACKUP_FOLDERS; do
            FILE_LIST[$C]="$FHS_BACKUP_FOLDER/$j"
            echo "$C) ${FILE_LIST[$C]}"
            let C=$C+1
        done
    else
        echo "ERROR: Seems that you don't have backups to restore."
        exit 1
    fi
}

# Choosing the backup
chooseBackup() {
    BACKUP_DIR_NUMBER=""
    echo
    read -p "Please enter the number of the backup to restore: " BACKUP_DIR_NUMBER

    if [ -z "$BACKUP_DIR_NUMBER" ] || [ $BACKUP_DIR_NUMBER -le 0 ] || [ $BACKUP_DIR_NUMBER -ge $C ]; then
        echo "ERROR: You did not choose a correct backup number"
        exit 1
    fi

    if [ $BACKUP_DIR_NUMBER -ge $FHS_NUMBER ]; then
        if [ ! $isFhs ]; then
            echo "ERROR: Cannot recover FHS backup into a non FHS Artifactory RPM"
            exit 1
        fi
        needsEtcConversion=false
    else
        if $isFhs; then
            needsEtcConversion=true
        else
            needsEtcConversion=false
        fi
    fi

    BACKUP_DIR="${FILE_LIST[$BACKUP_DIR_NUMBER]}"
    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
        echo "ERROR: Backup number $BACKUP_DIR_NUMBER provide directory $BACKUP_DIR which does not exists!"
        exit 1
    fi

    if [ ! -d "$BACKUP_DIR/data" ] || [ ! -d "$BACKUP_DIR/etc" ]; then
        echo "ERROR: Data and conf directories $BACKUP_DIR/data, $BACKUP_DIR/etc not found. Nothing to recover!"
        exit 0
    fi

    # Check if it is a 2.5.2 backup
    if [ -L "$BACKUP_DIR/etc" ] || [ -L "$BACKUP_DIR/tomcat" ]; then
        echo "INFO: Backup of Artifactory previous to 2.5.x detected."
        echo "ERROR: Cannot restore from Artifactory 2.5.x version backups."
        exit 1
    fi
}

checkServiceStatus() {
    service artifactory status
    if [ $? -eq 0 ]; then
        echo "Please notice: Need to stop running Artifactory service before recovering backup."
        read -p "Continue [Y/n]? " CONTINUE_INSTALL
        if [[ "${CONTINUE_INSTALL}" =~ [nN] ]]; then
            echo
            echo "Please make sure to stop Artifactory process before retrying backup recovery."
            echo "Press enter to quit..."
            read
            exit 0
        fi
        service artifactory stop || exit $?
    fi
}

moveData() {
    BACKUP_DATA_FOLDER=""
    DATA_FOLDER="$ARTIFACTORY_HOME/data"
    if [ -d "$DATA_FOLDER" ]; then
        echo
        echo "Please notice: An existing Artifactory data folder has been found at '${DATA_FOLDER}' and can be kept aside."
        read -p "Continue [Y/n]? " CONTINUE_INSTALL
        if [[ "${CONTINUE_INSTALL}" =~ [nN] ]]; then
            echo
            echo "Please make sure to move aside the current data folder before continuing."
            echo "Press enter to quit..."
            read
            exit 0
        fi
        BACKUP_DATA_FOLDER=${DATA_FOLDER}.${CURRENT_TIME}
        echo
        echo "INFO: Moving the Artifactory data folder to '${BACKUP_DATA_FOLDER}'. You may remove it later."
        mv $DATA_FOLDER $DATA_FOLDER.$CURRENT_TIME || exit $?
    fi

    echo "INFO: Moving $BACKUP_DIR/data into $DATA_FOLDER"
    mv $BACKUP_DIR/data $DATA_FOLDER || exit $?

    if [ `ls $BACKUP_DIR | grep mysql-connector` ]; then
        echo "INFO: Restoring MySQL connector"
        'cp' $BACKUP_DIR/mysql-connector* $ARTIFACTORY_BIN_HOME/tomcat/lib || exit $?
    fi

    # Ownership
    chown -R artifactory. $ARTIFACTORY_HOME || exit $?
}

moveEtc() {
    if [ -d "$ETC_FOLDER" ]; then
        if [ -z "$BACKUP_DATA_FOLDER" ]; then
            BACKUP_ETC_FOLDER=/tmp/artifactory.etc.${CURRENT_TIME}
            echo
            echo "INFO: No original Data folder found. Current Artifactory etc folder will be moved to temp folder '${BACKUP_ETC_FOLDER}'."
            mv $ETC_FOLDER $ETC_FOLDER.$CURRENT_TIME || exit $?
        else
            echo
            echo "Please notice: An existing Artifactory etc folder has been found at '${ETC_FOLDER}' and can be kept aside."
            read -p "Continue [Y/n]? " CONTINUE_INSTALL
            if [[ "${CONTINUE_INSTALL}" =~ [nN] ]]; then
                echo
                echo "Please make sure to move aside the current etc folder before retrying backup recovery."
                echo "Press enter to quit..."
                read
                exit 0
            fi
            BACKUP_ETC_FOLDER=${ETC_FOLDER}.${CURRENT_TIME}
            echo
            echo "INFO: Moving the Artifactory etc folder to '${BACKUP_ETC_FOLDER}'. You may remove it later."
            mv $ETC_FOLDER $ETC_FOLDER.$CURRENT_TIME || exit $?
        fi
    fi

    echo "INFO: Restoring $BACKUP_DIR/etc into $ETC_FOLDER"
    'cp' -r $BACKUP_DIR/etc $ETC_FOLDER || exit $?
    if $needsEtcConversion; then
        echo "INFO: Converting etc path values to FHS layout"
        sed --in-place -e "
            s#/var/lib/artifactory/run#/var/opt/jfrog/run#g;
            s#/var/lib/artifactory#$ARTIFACTORY_HOME#g;
            s#/opt/artifactory#$ARTIFACTORY_BIN_HOME#g;
            " $ETC_FOLDER/default || exit $?
    fi
    chown -R artifactory. $ETC_FOLDER || exit $?
}

# Run them all!
checkCurrentInstall && listCurrentBackups && chooseBackup && \
checkServiceStatus && moveData && moveEtc

echo
echo "The recovery process was completed successfully!"
echo "You can now start Artifactory."
echo "Press enter to exit..."
read
exit 0

