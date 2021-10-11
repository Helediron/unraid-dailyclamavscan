#!/bin/bash
#
# This script runs antivirus scan over selected Unraid shares.
# You can select one day in a week when the script runs another set of shares.
# Requires ClamAV container from Unraid Community Apps.
# Further details: https://hub.docker.com/r/tquinnelly/clamav-alpine

# Edit these parameters:
# List of Unraid shares to scan under /mnt/user. Check YOUR Unraid "Shares" tab. 
# Put a space between each share name.
FOLDERSDAILY="isos yourshare"
FOLDERSWEEKLY="isos yourshare bigshare hugeshare"
# Select which day is weekly scan day (1=mon, 7=sun).
WEEKLYDAY=2

# Create new Unraid user script:
# - "Add New Script", give name "daily_avscan" and save.
# - Click the cogwheel at the new line, "Edit Script".
# - Copypaste this whole script into the window and save. 
# Best to run scheduled, e.g. set custom schedule to
# "0 18 * * *" to run the scan each afternoon at 18:00

# Install ClamAV Docker container and edit container parameters:
# Switch to advanced mode (click basic mode at top right) and change
# "Post parameters" to "-i -f /scan/appdata/clamav/clamavtargets.txt".
# This tells the scanner to use a target list in a file instead of 
# scanning every Unraid share.
# Note that first run will fail with error because we have not yet run
# the user script which creates the file.

# Apply the new container configuration and let the container finish its first run.
# Switch back to user scripts and run manually the "daily_avscan". This may take very long time.

# If you want to interrupt a scan, stop the ClamAV container and the script stops soon after.

# End of instructions and parameters.


#Technical parameters
# name of the container.
CONTAINER=ClamAV
# Location of ClamAV application data folder in Unraid host. Note that this matches with
# "Post parameter" /scan/appdata/clamav, where in-container /scan is mapped to /mnt/user.
HOSTAPPDATA=/mnt/user/appdata/clamav
# Notify program
NOTIFY=/usr/local/emhttp/plugins/dynamix/scripts/notify

# Check if container is running (should not)
count=`docker ps | grep -c $CONTAINER`
if [ $count -gt 0 ]; then
  echo "$CONTAINER is already running, skipping"
  $NOTIFY -e "Antivirus Scan" -s "Antivirus Scan NOT Started" -d "Container is already running" -i "warning"
  exit 1
fi

# Select folders to scan, daily or weekly
day=`date +%u`
[ $day -ne $WEEKLYDAY ] && FOLDERS=`echo $FOLDERSDAILY` || FOLDERS=`echo $FOLDERSWEEKLY`

echo Creating scan list: $FOLDERS
rm $HOSTAPPDATA/clamavtargets.txt 2> /dev/null
for f in $FOLDERS
do
  if [ -d "/mnt/user/$f" ]; then
    echo "/scan/$f" >> $HOSTAPPDATA/clamavtargets.txt
  else
    echo "Can't find share: /mnt/user/$f"
  fi
done
echo "Scan targets:"
cat $HOSTAPPDATA/clamavtargets.txt

echo Starting scanner container
stat=`docker start $CONTAINER` 2> /tmp/avscancheck.txt
if [ "$stat" != "$CONTAINER" ]; then
  message=`echo "Failed starting $CONTAINER, ";head -2 /tmp/avscancheck.txt`
  rm /tmp/avscancheck.txt
  echo "$message"
  $NOTIFY -e "Antivirus Scan" -s "Antivirus Scan NOT Started" -d "$message" -i "warning"
  exit 1
fi
rm /tmp/avscancheck.txt
$NOTIFY -e "Antivirus Scan" -s "Antivirus Scan Started" -d "$CONTAINER Started" -i "normal"

echo Waiting scanner to finish...
docker wait $CONTAINER

echo Checking scanner logs
docker logs $CONTAINER 2>/dev/null | grep FOUND > /tmp/avscanlog.txt
count=`cat /tmp/avscanlog.txt | wc -l`
infected="No infections found"
if [ $count -gt 0 ]; then
  infected=`echo "Infected files: $count, "; [ $count -gt 10 ] && echo "(First ten) ";head -10 /tmp/avscanlog.txt`
fi
rm /tmp/avscanlog.txt
$NOTIFY -e "Antivirus Scan" -s "Antivirus Scan Finished" -d "$infected" -i "normal"
echo Scan done.
