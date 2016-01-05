# OpenShift Artifactory Cartridge

This cartridge runs Artifactory on OpenShift (Artifactory requires Java, so you will need that as well)

### Clean Installation (new app)

    rhc create-app YOUR_APP_NAME https://cartreflect-claytondev.rhcloud.com/reflect?github=andershedstrom/openshift-community-artifactory https://cartreflect-claytondev.rhcloud.com/reflect?github=andershedstrom/openshift-community-oracle-jdk-8

### Existing app with Java available

    rhc add-cartridge "https://cartreflect-claytondev.rhcloud.com/reflect?github=andershedstrom/openshift-community-oracle-jdk-8" -a YOUR_APP_NAME


Give some time to start up...

For the Artifactory user guide please visit: [Jfrog wiki](http://wiki.jfrog.org/confluence/display/RTF)


    The default administrator user is:

    username: admin
    password: password
