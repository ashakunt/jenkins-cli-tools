#!/bin/sh
blacklist="userContent \${WORK_DIR}"
backupdir=/home/master/backups/jenkins

# locations
server=http://buildserver:8080
groovy=/home/master/maintenance/status.groovy
clijar=/home/master/maintenance/jenkins-cli.jar

#credentials
user=$(cat /home/master/maintenance/.buildbotcreds-wumpus.name | cut -d ',' -f1)
pass=$(cat /home/master/maintenance/.buildbotcreds-wumpus.name | cut -d ',' -f2)

cd /var/lib/jenkins

dirs=$(echo */)
#dirs=$(ls -d */)

today=$(date +%Y-%m-%d)

echo "---- All existing dirs at JENKINS_HOME (/var/lib/jenkins) ----"
for dir in $dirs
do
    echo " + $dir"
done

directories="$dirs"

echo "---- Cleaning up blacklisted directories ----"
for black in $blacklist
do
    echo " - Removing blacklisted directory: $black"
    directories=$(echo $directories | sed -e "s:$black/::g")
done

echo "---- Directories to backup ----"
for dir in $directories
do
    echo " ++ $dir"
done

java -jar $clijar -s $server groovy $groovy --username $user --password $pass | grep WAIT_MORE -A 10
waitmore=$?
waitcount=0

maxwait=600
waitsecs=60

while [ $waitmore -eq 0 -a $waitcount -lt $maxwait ]; do
    sleep $waitsecs
    java -jar $clijar -s $server groovy $groovy --username $user --password $pass | grep WAIT_MORE -A 10
    waitmore=$?
    waitcount=$(($waitcount+1))
done

if [ $waitcount -eq $maxwait ]; then
    echo "Reached waiting limit of $(($waitcount*$waitsecs)) seconds, will abort now!"
    exit 1
fi

if [ $waitmore -ne 0 ]; then
    echo "Stop jenkins (safe-shutdown)"
    #java -jar $clijar -s $server safe-shutdown --username $user --password $pass 

    /usr/sbin/service jenkins stop

    echo "Taking backup now"

    mkdir -p $backupdir/$today

    backup=$backupdir/$today/jenkins.tar.gz

    # create the backup
    tar -czvf $backup $directories *.xml --exclude=*outOfOrderBuilds* --exclude=*/archive$ --exclude-vcs --exclude-caches-all | tee $backup.filelist.txt

    if [ $? -ne 0 ]; then
        echo "ERROR Occured while running backup. Please see: $backup.filelist.txt for errors."
    fi

    echo "Putting jenkins up again"
    /usr/sbin/service jenkins start
fi

# do some clean up
# policy: last backup from every month kept forever
