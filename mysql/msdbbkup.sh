#!/bin/bash
#
#=============================================================
# This script will use mysqldump against the running mysqld
# to backup each schema, and then the whole database.
#
# ASSUMPTIONS
# - Written and tested against MySQL CE 5.x on CentOS 5.x.
# - Paths etc. based on Ren's previous database environments.
# - A sysadmin NFS share is mounted on the db host.
# - Individual schema dumps are for devs local db refresh; 
#   whole database dumps are for "disaster recovery".
# - The schemas/databases are large and storage space is not.
# - There is someone who reads the email reports to breakfix.
# - Space conservation is important. 
# - The network is blazing fast.
# - Customization is expected and necessary. Compensate.
# - The database may be a master.
# - Stuff happens. Collect basic forensic info.
# - YMMV. 
#
# Peace,
# Ren
#
#=============================================================

# -----------------------------------------------------------
# SET UP VARIABLES 
# -----------------------------------------------------------

# Accept date as command line argument for manual run, otherwise
# set to today's date because we're running from cron

echo
echo "Usage: ./msdbbkup.sh"
echo "       ./msdbbkup.sh <date>"
echo
echo "       where <date> is: \`date '+%Y%m%d_%H%M_%N'\`"
echo

DATE=$1

echo Command line gave me $DATE

if [ -z $DATE ]
then
  DATE=`/bin/date '+%Y%m%d_%H%M_%N'`
  echo Using $DATE that I just made up because that I did not get a command line arg...
fi

PROGNAME=`basename $0 .sh`
MYDATE=`/bin/date '+%Y-%m-%d'`
HOST=`/bin/hostname -s`
RECIPIENTS="{EMAIL ADDRESS(ES)}"
SUBJECT="{APP/DB NAME} {DEV||TEST||PROD}  MYSQLDUMP Report"

# set the destination for the backups (stored by date)
# "dbbackups" directory is assumed to be an NFS share
BKHM=/dbbackups/${HOST}_backups/mysql-backups
DESTDIR=$BKHM/$DATE

# this variable is implicity +1 in the find command
KEEPDAYS=2

export TMPDIR=/tmp
export OUTFILE=$TMPDIR/tempfile-$PROGNAME-$$-$DATE.out
export TMPFILE=$TMPDIR/tempfile-$PROGNAME-$$-$DATE.tmp

# -----------------------------------------------------------
# START THE WORK
# -----------------------------------------------------------

# Clear the temp files
cp /dev/null $OUTFILE
cp /dev/null $TMPFILE

# Cleaning old backups to make space for the new one
/usr/bin/find $BKHM -type d -ctime +${KEEPDAYS} -exec /bin/rm -rf {} + 1>> $OUTFILE 2>&1

echo -e "These backups will be written to: $DESTDIR \n" >> $OUTFILE
mkdir $DESTDIR

# Dumping all databases will include the mysql system database needed for restoring users, privs, etc.
echo -e "Now dumping all the databases into one big gzball... \n"  >> $OUTFILE
#### this command should be supported by a secure login mechanism for the MYSQLDUMP user.
/usr/bin/mysqldump -u {MYSQLDUMP USER} -x --all-databases --flush-logs | gzip -9 > $DESTDIR/${HOST}_all-db.sql.gz

## Next dump each schema separately

# collect the current database instances
#### this command should be supported by a secure login mechanism for the backup user.
mysql -u {MYSQLDUMP USER} -e 'show databases;' | grep -v Database | grep -v information_schema | grep -v amonitordb > $TMPFILE
echo 

for DB in `cat $TMPFILE`
do
  # capture time along the way to see what's going on in morning if there's any issues.
  /bin/date >> $OUTFILE
  echo backing up instance: $DB  >> $OUTFILE
  #### this command should be supported by a secure login mechanism for the backup user.
  /usr/bin/mysqldump -u {MYSQLDUMP USER} $DB --flush-logs | gzip -9 > $DESTDIR/${HOST}_${DB}-db.sql.gz
done

# capture time along the way to see what's going on in morning if there's any issues.
/bin/date >> $OUTFILE
echo all individual instances dumped >> $OUTFILE

# This is optional and necessarily customizable
# The backup script itself is included for troubleshooting purposes
echo "backing up critical files related to mysql db and host..." >> $OUTFILE
/bin/cp /etc/my.cnf $DESTDIR/${HOST}_my.cnf
/bin/cp /var/lib/mysql/${HOST}-*bin* $DESTDIR
/bin/cp /root/bin/msdbbkup.sh $BKHM/${HOST}_msdbbkup.sh
/bin/cp /root/bin/syncdb.sh $BKHM/${HOST}_syncdb.sh

echo "backing up the logs in case there's an issue with the dump...."
/bin/cp /var/log/mysqld.log $BKHM

# Remove old binary logs to conserve disk space
echo "cleaning up mysql binary logs up until midnight today..." 
#### this command should be supported by a secure login mechanism for the backup user.
mysql -u {MYSQLDUMP USER} -e "purge master logs before '${MYDATE} 00:00:01';"

# Cleaning up after myself
/usr/bin/find $TMP -type f -name "tempfile-$PROGNAME*" -ctime +${KEEPDAYS} -exec rm -rf {} + 1>> $OUTFILE 2>&1

echo "===" >> $OUTFILE
/bin/date >> $OUTFILE

# This is because different systems use different versions of dump script
echo "Email from: $PROGNAME" >> $OUTFILE

# Send the report to someone who cares and will read and act on it every morning
/bin/mailx -s "$DATE - $SUBJECT - $HOST" $RECIPIENTS < $OUTFILE

# If we make here, everything has run cleanly. Any issues with the dump are rooted elsewhere.
exit 0
