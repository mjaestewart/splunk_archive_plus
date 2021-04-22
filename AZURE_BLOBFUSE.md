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
sudo -u splunk blobfuse /home/splunk/splunkarchive --tmp-path=/mnt/resource/blobfusetmp -o attr_timeout=240 -o entry_timeout=240 -o negative_timeout=120 --config-file=/home/splunk/fuse_connection.cfg --log-level=LOG_DEBUG --file-cache-timeout-in-seconds=120
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

### Persisting

1. Make sure the fuse package is installed (e.g. yum install fuse)
2. Update connection.cfg file with your storage account information.
3. Edit /etc/fstab with the blobfuse script.

Add the following line to use mount.sh:

```bash
/<path_to_blobfuse>/mount.sh /home/splunk/splunkarchive fuse _netdev
```

OR

Add the following line to run without mount.sh

```bash
blobfuse /home/azureuser/mntblobfuse fuse delay\_connect,defaults,\_netdev,--tmp-path=/home/azureuser/tmppath,--config-file=/home/azureuser/connection.cfg,--log-level=LOG\_DEBUG,allow\_other 0 0
```

(Note: you can omit the delay\_connect option after fuse if you do not want to wait for any dependent services, I left it there to prevent race conditions where sometimes fuse services take a while to load and fstab executes before that)

---

## [](https://github.com/Azure/azure-storage-fuse/wiki/2.-Configuring-and-Running#unmounting)Unmounting

The standard way to unmount a FUSE adapter is to use 'fusermount': 

```bash
fusermount -u /home/splunk/splunkarchive
```
