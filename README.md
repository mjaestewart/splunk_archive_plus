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

---

## Mounting Blob Storage to Indexers

---

## [](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-how-to-mount-container-linux)Overview

[Blobfuse](https://github.com/Azure/azure-storage-fuse) is a virtual file system driver for Azure Blob storage. Blobfuse allows you to access your existing block blob data in your storage account through the Linux file system. Blobfuse uses the virtual directory scheme with the forward-slash '/' as a delimiter.

This guide shows you how to use blobfuse, and mount a Blob storage container on Linux and access data. To learn more about blobfuse, read the details in [the blobfuse repository](https://github.com/Azure/azure-storage-fuse).

## [](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-how-to-mount-container-linux)Install blobfuse on Linux

Blobfuse binaries are available on [the Microsoft software repositories for Linux](https://docs.microsoft.com/en-us/windows-server/administration/Linux-Package-Repository-for-Microsoft-Software) for Ubuntu, Debian, SUSE, CentoOS, Oracle Linux and RHEL distributions. To install blobfuse on those distributions, configure one of the repositories from the list. You can also build the binaries from source code following the [Azure Storage installation steps](https://github.com/Azure/azure-storage-fuse/wiki/1.-Installation#option-2---build-from-source) if there are no binaries available for your distribution.

Blobfuse supports installation on Ubuntu versions: 16.04, 18.04, and 20.04, RHELversions: 7.5, 7.8, 8.0, 8.1, 8.2, CentOS versions: 7.0, 8.0, Debian versions: 9.0, 10.0, SUSE version: 15, OracleLinux 8.1 . Run this command to make sure that you have one of those versions deployed:

- Enterprise Linux 6 (EL6)

 ```bash
sudo rpm -Uvh https://packages.microsoft.com/config/rhel/6/packages-microsoft-prod.rpm
```

- Enterprise Linux 7 (EL7)

```bash
sudo rpm -Uvh https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm
```

- Enterprise Linux 8 (EL8)

```bash
sudo rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
```

- [](https://docs.microsoft.com/en-us/windows-server/administration/Linux-Package-Repository-for-Microsoft-Software)Installing Blobfuse on RHEL 8

```bash
# Install repository configuration
curl -sSL https://packages.microsoft.com/config/rhel/8/prod.repo | sudo tee /etc/yum.repos.d/microsoft-prod.repo

# Install Microsoft's GPG public key
curl -sSL https://packages.microsoft.com/keys/microsoft.asc > ./microsoft.asc
sudo rpm --import ./microsoft.asc
```

---

### Prepare for mounting

Blobfuse provides native-like performance by requiring a temporary path in the file system to buffer and cache any open files. For this temporary path, choose the most performant disk, or use a ramdisk for best performance.

---

### Use an SSD as a temporary path

In Azure, you may use the ephemeral disks (SSD) available on your VMs to provide a low-latency buffer for blobfuse. In Ubuntu distributions, this ephemeral disk is mounted on '/mnt'. In Red Hat and CentOS distributions, the disk is mounted on '/mnt/resource/'.

Make sure your user has access to the temporary path:

```bash
sudo mkdir /mnt/resource/blobfusetmp -p
sudo chown splunk /mnt/resource/blobfusetmp
```

---

### [](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-how-to-mount-container-linux#configure-your-storage-account-credentials)Configure your storage account credentials

Create this file using:

```bash
vi /home/splunk/fuse_connection.cfg
```

Blobfuse requires your credentials to be stored in a text file in the following format:

```bash
accountName myaccount
accountKey storageaccesskey
containerName mycontainer
```

The `accountName` is the prefix for your storage account - not the full URL.

Once you've created and edited this file, make sure to restrict access so no other users can read it.

```bash
chmod 600 /home/splunk/fuse_connection.cfg
```

If you have created the configuration file on Windows, make sure to run `dos2unix` to sanitize and convert the file to Unix format.

---

### [](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-how-to-mount-container-linux#create-an-empty-directory-for-mounting)Create an empty directory for mounting

```bash
mkdir /home/splunk/splunkarchive
```

---

## [](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-how-to-mount-container-linux#mount)Mount

**`Note`**

For a full list of mount options, check [the blobfuse repository](https://github.com/Azure/azure-storage-fuse#mount-options).

To mount blobfuse, run the following command with your user (splunk account). This command mounts the container specified in '/path/to/fuse\_connection.cfg' onto the location '/mycontainer'.

```bash
sudo -u splunk blobfuse /home/splunk/splunkarchive --tmp-path=/mnt/resource/blobfusetmp --config-file=/home/splunk/fuse_connection.cfg -o entry_timeout=240 -o negative_timeout=120 --log-level=LOG_DEBUG --file-cache-timeout-in-seconds=300
```

You should now have access to your block blobs through the regular file system APIs. The user who mounts the directory is the only person who can access it, by default, which secures the access. To allow access to all users, you can mount via the option `-o allow_other`.

```bash
cd /home/splunk/splunkarchive
mkdir test
echo "hello world" > test/blob.txt
```

---
You are now ready to use the [](https://github.com/mjaestewart/splunk_archive_plus)**`Splunk Archive Plus App`** with Azure Blob Storage!

---

## Lab Testing OOB

- The script has the `source copy path` set to `/opt/frozen` on the local search peers which needs to be changed in the `ARCH_CP_PATH` variable.
- Can deploy the `splunk_archive_plus` app via Splunk Cluster Master to all search peers.
- Ensure to `chown -R /opt/` where a `frozen` dir will be created in `/opt/` for the frozen buckets being copied `(local testing)`.
  - `Subdirectories` are created and named by `index name` for the `copy destination directory`.
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
  - `ARCH_CP_PATH='/home/splunk/splunkarchive'`

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
