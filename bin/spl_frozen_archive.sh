#!/bin/bash

# This script is designed to copy Splunk Archive buckets to an Azure Blob Storage.

# After the successful copy of the archive files a conditional check will ensure the 
# copy was successful then delete the originating archive buckets from the frozen source directory.

# If the copy fails then no buckets will be deleted. 
# Check the log file /opt/splunk/var/log/splunk/frozen_copy.log

# Ensure the script has the proper permissions to copy and delete buckets.

# Typically, the Azure Blob Storage is mounted or presented to a proxy server.

# Ensure the account running the frozen script has permissions on the proxy server 
# to read and write. 

## Setting Global Variables
## Set the ARCHIVE_BUCKET value to be the Azure Blob Storage Proxy Host (i.e. azurehostblob)
IDX_PATH='/opt/splunk/var/lib/splunk'  ## SET abslute path to /opt/splunk/var/lib/splunk
ARCH_CP_PATH='/opt/frozen'  ## SET absolute path to where archive copies will be transferred to
FROZEN_DB_NAME='frozen'  ## SET the name of directory where original frozen data lives
FROZEN_CP_LOG='/opt/splunk/var/log/splunk/ARCHIVE_copy.log'  ## set absolute path where Archive Copy log will reside
RB_ARCH_RM_LOG='/opt/splunk/var/log/splunk/ARCHIVE_rb_remove.log'  ## SET absolute path where Archive rb_ Removal log will reside
date_timestamp="$(date --utc +%FT%TZ)" ## Log UTC entry time
log_timestamp="$(date +%s)" ## log appended with epoch timestamp for rolling logs past 5 logs
arch_idx=/opt/splunk/var/log/splunk/ARCHIVE_list.log  ## set absulute path for archive list
dup_idx=/opt/splunk/var/log/splunk/ARCHIVE_duplicates_list.log  ## set absolute path for duplicates list
dupes=$(echo $dup_idx | awk '{print $2}' | sed -e 's,/journal.gz,,')  ## finding duplicate buckets variable
rm_dupes=/opt/splunk/var/log/splunk/ARCHIVE_rm_dupes_list.log  ## set absolute path for duplicates removal list


## Azure Splunk Archive Copy Function
function spl_arch_copy() {

if [[ -f $FROZEN_CP_LOG ]]; then  ## Checking log existence
        mv $FROZEN_CP_LOG "$FROZEN_CP_LOG"."$log_timestamp"  ## Rolling log
fi

## Purge rolling logs if more than n exist
## path and name of script
archive_script=0
fancy_graphics=0
n=4  ## setting number of rolled logs to keep + original log
c=0  ## setting a value of zero
 
while [[ $( ls "${FROZEN_CP_LOG}".* | sort | wc -l ) -gt ${n} ]]; do  ## getting number of logs
  del_me="$( ls "${FROZEN_CP_LOG}".* | sort | head -n1 )"  ## setting log variable
  if [[ ${archive_script} == 0 ]]; then  
    rm "${del_me}"; 
  else
    rm -i "${del_me}";
  fi
  if [[ ! -f "${del_me}" ]]; then  ## testing if logs do not exist
    c=$((c+1))  ## incrementing c variable
  fi
done

if [ ${c} -gt 0 ] && [ ${fancy_graphics} == 1 ]; then  ## testing c > 0 && fancy_graphics equal to 1
  echo "[+] $( date -R ) : Purged ${c} old ARCHIVE_rb_remove.log files\n" >> $RB_ARCH_RM_LOG
fi

# changing dir and if not exist then exit funciton
cd $IDX_PATH || echo ''$IDX_PATH' Does not exist. Exiting.' || exit

## Looking for db_ & rb_ archive buckets
for file in $(find . -name '*.gz' -printf "%h\n" | grep $FROZEN_DB_NAME);
do
        ## Setting scope variables
        RELATIVE_PATH=$(echo $file | sed 's/\.\///')
        BUCKET_DETAILS=$(echo $RELATIVE_PATH | awk -F/ '{print "index="$1 " " "bucket="$3}')
        md5_FILE_NAME=$(echo $RELATIVE_PATH | awk -F/ '{print $3}')
        md5_HASH=$(cat $file/$md5_FILE_NAME.md5 | head -c32)

        if [ ! -e $ARCH_CP_PATH/$RELATIVE_PATH ]; then  ## Making the destination dir same as source
                mkdir -p $ARCH_CP_PATH/$RELATIVE_PATH  # directory does not exist. Creating new dir
        fi

        if [ ! -f $file/$md5_FILE_NAME.md5 ]; then  ## creating md5sum file hashes for comparison
                md5sum $file/journal.gz > $file/$md5_FILE_NAME.md5  ## creating md5 checksum file
        fi

        ## Conditionally checking the generated md5 hash against the journal.gz archive
        ## Then Copying the Archived Buckets & MD5 file -- overwriting if necessary
        ## USE MC commands if needed for AZURE instead of cp
        ##              example: /bin/mc cp -f $file azure/$S3_ARCHIVE_BUCKET/$RELATIVE_PATH > /dev/null
        if md5sum --status -c <(echo $md5_HASH $file/journal.gz); then
                cp -f -u -p $file/*.gz $file/*.md5 $ARCH_CP_PATH/$RELATIVE_PATH > /dev/null ## Change command per your copy method.
                MD5_MES='MD5_Check_PASSED Copying frozen '$file'/journal.gz to '$ARCH_CP_PATH'/'$RELATIVE_PATH'. '
        else 
                MD5_MES='MD5_Check_FAILED Not copying '$ARCH_CP_PATH'/'$RELATIVE_PATH'. Exiting. '
        fi

        ## Conditionally checking the generated md5 hash against the copied journal.gz archive
        ## If copy is successful and hash is validated then delete db_ and rb_ archive buckets at source
        if md5sum --status -c <(echo $md5_HASH $ARCH_CP_PATH/$RELATIVE_PATH/journal.gz); then
                src_arch_folder=$(echo $file | sed -e 's,/rawdata/,,')
                #rm -rf $src_arch_folder  ## REMOVING ORIGINAL ARCHIVES
                RES='SUCCESS'
                MES='COPY_SUCCESSFUL of archive '$file'/journal.gz successfully to '$ARCH_CP_PATH'/'$RELATIVE_PATH'. Deleted '$file'/journal.gz. '
        else
                RES='FAILED'
                MES='COPY_FAILED of archive '$file'/journal.gz to '$ARCH_CP_PATH'/'$RELATIVE_PATH'. Delete operation cancelled. '
        fi

        echo
        echo ''$date_timestamp' DeepFreezing '$BUCKET_DETAILS' md5='$md5_HASH' md5_result='$MD5_MES' copy_result='$RES' message='$MES' ' >> $FROZEN_CP_LOG
done

}


## Removing Duplicate Replicated Archive Buckets
function spl_rm_rb_dupes() {

if [[ -f $RB_ARCH_RM_LOG ]]; then ## Checking log existence
        mv $RB_ARCH_RM_LOG "$RB_ARCH_RM_LOG"."$log_timestamp" ## Rolling log
fi

## Purge rolling logs if more than n exist
## path and name of script
archive_script=0
fancy_graphics=0
n=4  ## setting number of rolled logs to keep + original log
c=0  ## setting a value of zero
 
while [[ $( ls "${RB_ARCH_RM_LOG}".* | sort | wc -l ) -gt ${n} ]]; do  ## getting number of logs
  del_me="$( ls "${RB_ARCH_RM_LOG}".* | sort | head -n1 )"  ## setting log variable
  if [[ ${archive_script} == 0 ]]; then  
    rm "${del_me}"; 
  else
    rm -i "${del_me}";
  fi
  if [[ ! -f "${del_me}" ]]; then  ## testing if logs do not exist
    c=$((c+1))  ## incrementing c variable
  fi
done

if [ ${c} -gt 0 ] && [ ${fancy_graphics} == 1 ]; then  ## testing c > 0 && fancy_graphics equal to 1
  echo "[+] $( date -R ) : Purged ${c} old ARCHIVE_rb_remove.log files\n" >> $RB_ARCH_RM_LOG
fi

## Removing deuplicate archive files based on md5 check across all 
if [ ! -f $arch_idx ]; then ## checking for duplicate list existence
        touch $arch_idx  ## creating archive list file 
        find $ARCH_CP_PATH -type f \! -type d -exec md5sum {} \; | sort | tee $arch_idx > /dev/null  ## building list of md5's in a sorted order
else
        rm "$arch_idx" ## removing old archive list
        #mv $arch_idx "$arch_idx"."$date_timestamp"  ## SET absolute path && mv $arch_idx $ARCH_CP_PATH/archive.tmp.$date
        find $ARCH_CP_PATH -type f \! -type d -exec md5sum {} \; | sort | tee $arch_idx > /dev/null  ## building list of md5's in a sorted order
fi

## Checking the journal.gz from all copied archives and all indexers for md5(32 bytes) duplicates in a row
if [ ! -f $dup_idx ]; then  ## checking for duplicate list existence
        touch $dup_idx  ## creating duplicates list
        sort -r $arch_idx | uniq -dw32 >> $dup_idx  ## sorting the archive list and uniquely identifying the md5's that are duplicates for the journal.gz files
        cat $dup_idx | awk '{print $2}' | sed -e 's,/journal.gz,,' >>$rm_dupes  ## printing path out of all bucket paths with journal.gz duplicates to build list
else
        rm "$dup_idx" ## removing old duplicate list 
        # mv $dup_idx "$dup_idx"."$date_timestamp"  ## SET absolute path && mv $dup_idx $ARCH_CP_PATH/duplicates.tmp.$date
        sort -r $arch_idx | uniq -dw32 >> $dup_idx  ## sorting the archive list and uniquely identifying the md5's that are duplicates for the journal.gz files
        cat $dup_idx | awk '{print $2}' | sed -e 's,/journal.gz,,' >>$rm_dupes  ## printing path out of all bucket paths with journal.gz duplicates to build list
fi

## reading the duplicates file and removing duplicate buckets and directories
if [ -f $rm_dupes ]; then
        while read path; do
                echo ''$date_timestamp' Removing duplicate archive bucket duplicate='$path'/journal.gz' >> $RB_ARCH_RM_LOG ## writing to log
                rm_data=$(echo $path | sed -n 's:^\(/[^/]\{1,\}/[^/]\{1,\}/[^/]\{1,\}/[^/]\{1,\}/[^/]\{1,\}\).*:\1:p')  ## extracting full path to duplicate bucket/journal.gz for removal
                rm -rf $rm_data </dev/null;
        done <"$rm_dupes" ## feeding rm_dupes.log entries for removal list back to while loop
        rm "$rm_dupes" ## removing removal duplicate list
        rm "$arch_idx" ## removing archive list
        rm "$dup_idx" ## removing duplicate list
        #mv $rm_dupes "$rm_dupes"."$date_timestamp" ## rolling the ARCHIVE_rm_dupes_list.log
else 
        echo ''$date_timestamp' Duplicate removal list does not exist. Restarting.' >> $RB_ARCH_RM_LOG && $(spl_rm_rb_dupes) ## No removal list was built. Starting function over. 
fi

}

## calling logical funcions in main
function main() {
     spl_arch_copy
     spl_rm_rb_dupes
}

## calling on main function
main "$@"
