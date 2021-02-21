# splunk_archive_plus

Dev'd by: Mark Stewart, M.Sc.
Organization: Splunk

This app provides a method of transferring frozen originating archive buckets from an indexer's coldToFrozenDir to an Azure Blob Storage via proxy server and MinIO, NAS, SAN, or AWS.

This app runs with the following components:

- inputs.conf = scripted input executes script on intervals AND monitors the scripting outputs
- indexes.conf = sets the indexes for event ingestion from the scripting output
- spl_frozen_archive.sh
  - copies the originating (db\_) and (rb\_) buckets from local frozen repositories to Azure blob via MinIo, NAS via cp, SAN via cp, or AWS via cli command.
  - MD5 sums are set on ALL frozen buckets/journal.gz files for integritey checks
  - MD5 sums are used to validate successful copy of archived data from source to destination
  - Removes ALL originating local frozen buckets on all search peers (db\_ AND rb\_) upon a successful copy
  - Deduplicates the replicated archive buckets (rb\_) and keeps ALL originating (db\_) buckets to save on storage footprint
  - Logs all events for copies, MD5 sums, and deduplicated replicated bucket removals
  - indexes logs in Splunk to index = archive\_copy, index = archive\_remove

## Prerequisites

- Set the coldToFrozenDir on the indexes to be rolled to frozen in indexes.conf
- Set the path to:
  - coldToFrozenDir = $SPLUNK_DB/INDEX_NAME/frozen
- Ensure the script has the proper permissions to copy and delete buckets on the search peers (indexers)
- Typically, the Azure Blob Storage is mounted or presented to a proxy server so minIo should be used
- Ensure the account running the frozen script has permissions on the proxy server
  to read and write.
- May need to chown -R splunk:splunk /opt/splunk

## Logic in the copy function

- The  script is designed to copy originating db\_ and rb\_ Splunk Archive buckets to an Azure Blob Storage
  or NAS, SAN, AWS, from the indexes coldToFrozenDir path
- All buckets are copied and deduplication takes place against those copied buckets preserving
  the originating db_ buckets first.
- After the successful copy of the originating local frozen buckets a conditional check will ensure the
  copy was successful then delete the local frozen buckets from the frozen directory.
- If the copy fails then no buckets will be deleted locally.
- MD5 sums are created on every file and used for integrity checks for copies
- All activity gets logged to /opt/splunk/var/log/splunk/ARCHIVE_copy.log

## Logic in the Replicated Archive Buckets function

- The script recursively finds all replicated frozen buckets in the coldToFrozenDir path
  that are replicated copies (rb_)
- A conditional check validates the successful existence of rb_ replicated frozen buckets
- if rb\_ journal.gz files exist alongside an originating db\_ bucket then remove the replicated rb\_ frozen buckets
- All activity gets logged to /opt/splunk/var/log/splunk/ARCHIVE_rb_remove.log

## Script spl\_frozen\_archive\.sh

- ** Be sure to set the global variable in the script
- ** If "frozen" is not the path in the coldToFrozenDir path then set
     the correct value on the global variable

     ** coldToFrozenDir = $SPLUNK_DB/_internal/frozen
     \- In the above reference the global variable would be set to:
              \- FROZEN_DB_NAME='frozen'

## Global Variables

- SET abslute path to /opt/splunk/var/lib/splunk
  - IDX_PATH='/opt/splunk/var/lib/splunk'

- SET absolute path to where archive copies will be transferred to
  - ARCH_CP_PATH='/opt/frozen'

- SET the name of directory where original frozen data lives
  - FROZEN_DB_NAME='frozen'

- SET absolute path where Archive Copy log will reside
  - FROZEN_CP_LOG='/opt/splunk/var/log/splunk/ARCHIVE_copy.log'

- SET absolute path where Archive rb\_ Removal log will reside
  - RB_ARCH_RM_LOG='/opt/splunk/var/log/splunk/ARCHIVE_rb_remove.log'

- Event UTC entry time
  - date_timestamp="$(date --utc +%FT%TZ)"

- log appended with epoch timestamp for rolling logs and keeping only 4 rolling logs
  - log_timestamp="$(date +%s)"

- SET absulute path for archive list
  - arch_idx=/opt/splunk/var/log/splunk/ARCHIVE_list.log

- SET absolute path for duplicates list
  - dup_idx=/opt/splunk/var/log/splunk/ARCHIVE_duplicates_list.log

- finding duplicate buckets variable
  - dupes=$(echo $dup_idx | awk '{print $2}' | sed -e 's,/journal.gz,,')

- SET absolute path for duplicates removal list
  - rm_dupes=/opt/splunk/var/log/splunk/ARCHIVE_rm_dupes_list.log

## **IMPORTANT TO NOTE**

- Line 88 in script is where the copy occurs
  ##Change cp command per your copy method. If Azure is being used then use MinIo
  - cp -f -u -p $file/*.gz $file/*.md5 $ARCH_CP_PATH/$RELATIVE_PATH > /dev/null

- Line 98 is where source removal of local frozen buckets and is currently commented out. Remove comment to activate removal.
  - #rm -rf $src_arch_folder  ## REMOVING ORIGINAL ARCHIVES

### inputs.conf comments

- The scripted inputs executes the script to enforce the time based interval of excution on the spl_frozen_archive.sh script.
- Change the inputs values as necessary.
- All script logging is output and monitored in /opt/splunk/var/log/splunk/
- Logic in the script only keeps a total of 5 log files.
- Every execution run of the script a log rotates and prunes the oldest.

### Scripted Inputs for Azure Frozen Copy Job

```bash
[script://./bin/spl_frozen_archive.sh]
disabled = 0
sourcetype = azure_copy
#for testing: every 2 mins
interval = 120
#execute every 24 hours
#interval = 86400

[monitor:///opt/splunk/var/log/splunk/ARCHIVE_copy.log*]
disabled = 0
sourcetype = archive_copy
index = archive_copy

[monitor:///opt/splunk/var/log/splunk/ARCHIVE_rb_remove.log*]
disabled = 0
sourcetype = archive_remove
index = archive_remove
```

### indexes.conf

- If there is an indexes all app then paste these stanzas into that app's indexes.conf
- Then remove this indexes.conf from the app

```bash
##Frozen Indexes
##If have an indexes all app then paste into that conf
##then remove this indexes.conf from the app

[archive_copy]
homePath = volume:primary/$_index_name/db
coldPath = volume:primary/$_index_name/colddb
thawedPath = $SPLUNK_DB/$_index_name/thaweddb
coldToFrozenDir = $SPLUNK_DB/$_index_name/frozen
frozenTimePeriodInSecs = 220752000

[archive_remove]
homePath = volume:primary/$_index_name/db
coldPath = volume:primary/$_index_name/colddb
thawedPath = $SPLUNK_DB/$_index_name/thaweddb
coldToFrozenDir = $SPLUNK_DB/$_index_name/frozen
frozenTimePeriodInSecs = 22075200
```
