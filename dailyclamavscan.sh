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
# The script writes these files to /mnt/user/appdata/clamav directory
# clamavloglast.txt: last scanlog extracted from container logs.
# clamavmaplog.txt: log how the user script was able to map to user shares.
# clamavtargets.txt: parameter file for ClamAV. Each line is a directory to be scanned.
#   The directory is container-internal path. You can make custom scans by editing this file
#   and running the container manually.

# End of instructions and parameters.


#Technical parameters
# name of the container.
CONTAINER=ClamAV
# Location of ClamAV application data folder in Unraid host. 
# Must match with container parameter "ClamAV Signatures:"
HOSTAPPDATA=/mnt/user/appdata/clamav
# Location of scanned directory. 
# Must match with container parameter "Folder to Scan:"
HOSTSCANDIR=/mnt/user
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
rm $HOSTAPPDATA/clamavmaplog.txt 2> /dev/null
maperrors=0
for f in $FOLDERS
do
  if [ -d "$HOSTSCANDIR/$f" ]; then
    echo "/scan/$f" >> $HOSTAPPDATA/clamavtargets.txt
	echo "Scanning container /scan/$f -> host $HOSTSCANDIR/$f"
	echo "Scanning container /scan/$f -> host $HOSTSCANDIR/$f" >> $HOSTAPPDATA/clamavmaplog.txt
  else
    echo "Warning: can't find share: $HOSTSCANDIR/$f"
    echo "Warning: can't find share: $HOSTSCANDIR/$f" >> $HOSTAPPDATA/clamavmaplog.txt
	maperrors=1
  fi
done

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
# The awk program extracts last run of the log
docker logs $CONTAINER 2>/dev/null | awk '/ClamAV process starting/{ buf=$0; c=0; found=1; next }
  ++c>0 { buf=(buf==""?"":buf ORS) $0 }
  END{ if(c>=2 && found)print buf }' > $HOSTAPPDATA/clamavloglast.txt
cat $HOSTAPPDATA/clamavloglast.txt | grep FOUND > /tmp/avscanfound.txt
count=`cat /tmp/avscanfound.txt | wc -l`
if [ $count -gt 0 ]; then
  infected=`echo "Infected files: $count, "; [ $count -gt 10 ] && echo "(First ten) ";head -10 /tmp/avscanfound.txt`
  $NOTIFY -e "Antivirus Scan" -s "Antivirus Scan Finished" -d "$infected" -i "warning"
elif [ $maperrors -gt 0 ]; then
  $NOTIFY -e "Antivirus Scan" -s "Antivirus Scan Finished" -d "No infections found, unknown shares" -i "warning"
else
  $NOTIFY -e "Antivirus Scan" -s "Antivirus Scan Finished" -d "No infections found" -i "normal"
fi
rm /tmp/avscanfound.txt
echo Scan done.
