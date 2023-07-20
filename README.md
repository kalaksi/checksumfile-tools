# checksumfile-tools
Tools for managing file integrity checksums using plain old files.  
  
These tools were inspired by `shatag` with 3 important differences:  
1. Written in bash (4.4) with usually no additional dependencies.
2. Data is stored using common files which makes it simpler and filesystem-agnostic if you don't mind the extra files ("SHA256SUMS"-file). Do note that this also means that the original checksums are kept even when copying files between filesystems. This provides protection against other software or user errors, but is mostly usable for data that doesn't change often.
3. Verification result and timestamp is stored in the checksum-file(s), so they are not lost.

Basically, these scripts form an extension for existing checksumming tools such as `sha256sum`.  
The main purpose is to make operating on directories simple and to provide functionality for periodic scrubbing/checking.
It's also possible add or delete files from the checksum file seamlessly.

Use `-h` to see the details of available configuration options.

### Examples
#### Default parameters, on a photo album

Create a checksum file for the selected directory:
```
./checksumfile-create.sh Photos/
  Photos:
    ./2018/birthday/abc.jpg
    ./2018/birthday/def.jpg
```

For more fine-grained management (recommended), create checksum files for immediate subdirectories.
`-u` allows updating existing checksum files. Otherwise the directory is skipped.
```
$ ./checksumfile-create.sh -d 1 -u Photos/
  Photos/2018:
    ./birthday/abc.jpg
    ./birthday/def.jpg
  Photos/2019:
    ./birthday/cake/abc.jpg
  Photos/2020:
    109 existing checksums available. Checking for new or deleted files...
    Added ./summer/abc.jpg
    Added ./summer/def.jpg

Completed without errors.
```

Ignore txt-files:
```
$ ./checksumfile-create.sh -f '-not -name "*.txt"' Photos/
```

Verify that they haven't changed:
```
$ ./checksumfile-verify.sh -p 2 Photos/

Processing directory Photos/ containing 3 available checksum files:
  Photos/2018:
    ./birthday/abc.jpg: OK
    ./birthday/def.jpg: OK
  Photos/2019:
    ./birthday/cake/abc.jpg: OK

Reached target percentage 2% of checked checksums.
3/116 checksums checked. 0 errors found!
```

Show status from checksumfile metadata. Less recently scanned are displayed first.
```
$ ./checksumfile-verify.sh -s Photos/

Processing directory Photos/ containing 3 available checksum files:
  Photos/2017:
    Last checked: never
  Photos/2018:
    Last checked: 2012-12-12_12:12:12
    Errors: 0
  Photos/2019:
    Last checked: 2012-12-12_12:12:13
    Errors: 1

0/116 checksums checked. 1 errors found!
```

Use quiet mode to only print files with errors (checksum or other) when verifying (or creating). Useful for automated jobs and logging.
```
$ ./checksumfile-verify.sh -q Photos/
/home/user/Photos/birthday/def.jpg
```
