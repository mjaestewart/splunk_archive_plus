# splunk_archive_plus

Dev'd by: Mark Stewart, M.Sc.
Organization: Splunk

This app provides a method of transferring frozen originating archive buckets from an indexer's coldToFrozenDir to an Azure Blob Storage via proxy server and MinIO, NAS, SAN, or AWS.

This app runs with the following components:

- `inputs.conf` = scripted input executes script on intervals AND monitors the scripting outputs
- `indexes.conf` = sets the indexes for event ingestion from the scripting output
- `spl_frozen_archive.sh`
  - copies the originating `(db_)` and `(rb_)` buckets from local frozen repositories to `Azure blob via MinIo`, `NAS via cp/scp`, `SAN via cp/scp`, or `AWS via cli command`.
  - `MD5 sums` are set on ALL frozen `buckets/journal.gz` files for integritey checks
  - `MD5 sums` are used to validate successful copy of archived data from source to destination
  - Removes ALL originating local frozen buckets on all search peers `(db_ AND rb_)` upon a successful copy
  - Deduplicates the replicated archive buckets `(rb_)` and keeps ALL originating `(db\_)` buckets to save on storage footprint
  - Logs all events for copies, MD5 sums, and deduplicated replicated bucket removals
  - indexes logs in Splunk to `index = archive_copy`, `index = archive_remove`

## Prerequisites

- Set the coldToFrozenDir on the indexes to be rolled to frozen in indexes.conf
- Set the path to:
  - `coldToFrozenDir = $SPLUNK_DB/INDEX_NAME/frozen`
- Ensure the script has the proper permissions to copy and delete buckets on the search peers (indexers)
- Typically, the Azure Blob Storage is mounted or presented to a proxy server so minIo should be used
- Ensure the account running the frozen script has permissions on the proxy server
  to read and write.
- May need to `chown -R splunk:splunk /opt/splunk`

## Lab Testing OOB

- The script has the `source copy path` set to `/opt/frozen` on the local search peers which needs to be changed in the `ARCH_CP_PATH` variable.
- Can deploy the `splunk_archive_plus` app via Splunk Cluster Master to all search peers.
- Ensure to `chown -R /opt/` where a `frozen` dir will be created in `/opt/` for the frozen buckets being copied `(local testing)`.
- Only 4 rolling logs are kept by default.
  - Change the `value` of `4` on `line 30` and `110` if you wish to keep more than `4 rolling logs`.
- `ARCHIVE_copy.log` & `ARCHIVE_rb_remove.log` exist in the `/opt/splunk/var/log/splunk` dir and will be collected by `Splunk inputs.conf`
- Ensure to change the `inputs.conf` scripted input interval to `2 mins` when testing OR `24 hrs` when not testing (`atribs & values already exist`).
- `Line 74` in the script is where the `copy` occurs. Change the command based on the copy method.
  - i.e.) `MinIO` is best used with `Azure blob storage` with a Proxy Server.
  - Can change `cp` to `scp` if going to a location off the server.
  - `AWS` cli commands can also be used.
- `Line 84` in the script is where the **removal** of the `local/source` buckets will take place.
  - `Uncomment Line 84` to remove the source buckets.
  - This line is `commented out by default` to prevent any `deletions` of data.
- `Run` a `search` in your `Splunk UI` for `(index=archive_copy OR index=archive_remove)` for complete logging results.
- **`Enjoy!`**

## Logic in the copy function

- The  script is designed to copy originating `db\_` and `rb\_` Splunk Archive buckets to an Azure Blob Storage
  or NAS, SAN, AWS, from the indexes coldToFrozenDir path
- All buckets are copied and deduplication takes place against those copied buckets preserving the originating `db_` buckets first.
- After the successful copy of the originating local frozen buckets a conditional check will ensure the
  copy was successful then delete the local frozen buckets from the frozen directory.
- If the copy fails then no buckets will be deleted locally.
- MD5 sums are created on every file and used for integrity checks for copies
- All activity gets logged to `/opt/splunk/var/log/splunk/ARCHIVE_copy.log`

## Logic in the Replicated Archive Buckets function

- The script recursively finds all replicated frozen buckets, both `rb_` and `db_`, in the coldToFrozenDir path
- A conditional check validates the successful existence of `rb_` replicated frozen buckets
- if `rb_` journal.gz files exist alongside an originating `db_` bucket then remove the replicated `rb_` frozen buckets
- All activity gets logged to `/opt/splunk/var/log/splunk/ARCHIVE_rb_remove.log`

## Script spl\_frozen\_archive\.sh

- ** Be sure to set the global variable in the script
- ** If `"frozen"` is not the path in the `coldToFrozenDir` path then set the correct value on the global variable
- ** `coldToFrozenDir = $SPLUNK_DB/_internal/frozen`
  - In the above reference the global variable would be set to:
    - `FROZEN_DB_NAME='frozen'`

## Global Variables

- **SET abslute path to /opt/splunk/var/lib/splunk**
  - `IDX_PATH='/opt/splunk/var/lib/splunk'`

- **SET absolute path to where archive copies will be transferred to**
  - `ARCH_CP_PATH='/opt/frozen'`

- **SET the name of directory where original frozen data lives**
  - `FROZEN_DB_NAME='frozen'`

- **SET absolute path where Archive Copy log will reside**
  - `FROZEN_CP_LOG='/opt/splunk/var/log/splunk/ARCHIVE_copy.log'`

- **SET absolute path where Archive rb\_ Removal log will reside**
  - `RB_ARCH_RM_LOG='/opt/splunk/var/log/splunk/ARCHIVE_rb_remove.log'`

- **Event UTC entry time**
  - `date_timestamp="$(date --utc +%FT%TZ)"`

- **log appended with epoch timestamp for rolling logs and keeping only 4 rolling logs**
  - `log_timestamp="$(date +%s)"`

- **SET absulute path for archive list**
  - `arch_idx=/opt/splunk/var/log/splunk/ARCHIVE_list.log`

- **SET absolute path for duplicates list**
  - `dup_idx=/opt/splunk/var/log/splunk/ARCHIVE_duplicates_list.log`

- **finding duplicate buckets variable**
  - `dupes=$(echo $dup_idx | awk '{print $2}' | sed -e 's,/journal.gz,,')`

- **SET absolute path for duplicates removal list**
  - `rm_dupes=/opt/splunk/var/log/splunk/ARCHIVE_rm_dupes_list.log`

## **IMPORTANT TO NOTE**

- **`Line 74`** in script is where the copy occurs
  - ##Change cp command per your copy method. If Azure is being used then use MinIo
    - `cp -f -u -p $file/*.gz $file/*.md5 $ARCH\_CP\_PATH/$RELATIVE\_PATH > /dev/null`

- **`Line 84`** is where source removal of local frozen buckets and is currently commented out. Remove comment to activate removal.
  - `#rm -rf $src\_arch\_folder  ## REMOVING ORIGINAL ARCHIVES`

### inputs.conf comments

- The scripted inputs executes the script to enforce the time based interval of excution on the `spl_frozen_archive.sh` script.
- Change the inputs values as necessary.
- All script logging is output and monitored in `/opt/splunk/var/log/splunk/`
- Logic in the script only keeps a total of `5 log files`.
- Every execution run of the script a log rotates and prunes the oldest.

### Scripted Inputs for Azure Frozen Copy Job

```bash
[script://./bin/spl_archive_plus.sh]
disabled = 0
sourcetype = archive_plus
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
homePath = volume:primary/archive_copy/db
coldPath = volume:primary/archive_copy/colddb
thawedPath = $SPLUNK_DB/archive_copy/thaweddb
coldToFrozenDir = $SPLUNK_DB/archive_copy/frozen
frozenTimePeriodInSecs = 220752000

[archive_remove]
homePath = volume:primary/archive_remove/db
coldPath = volume:primary/archive_remove/colddb
thawedPath = $SPLUNK_DB/archive_remove/thaweddb
coldToFrozenDir = $SPLUNK_DB/archive_remove/frozen
frozenTimePeriodInSecs = 22075200
```
