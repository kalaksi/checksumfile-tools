#!/usr/bin/env bash
# Copyright (C) 2017 kalaksi@users.noreply.github.com
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -eu -o pipefail

# Default values
declare HASH_BINARY="sha256sum"
declare CHECKSUM_FILE="SHA256SUMS"
declare -i DIR_DEPTH=1
declare -i UPDATE_EXISTING=0
# Only include files that are over 50kiB
declare FIND_PARAMS="-size +50k"

function _help {
    cat << EOF

Usage: $0 [-b hash_binary_name] [-d subdir_depth] [-f "find_params"] [-n checksum_file_name] [-u] directory_name

Recursively creates checksum files using $HASH_BINARY. Option -d will define the subdirectory level
on which the files are created. The checksum file will contain checksums of files in and under that directory.
Integrity verification can be done directly with sha256sum or by using $(echo -e "\033[1mchecksumfile-verify.sh\033[0m").

Options:
  -f  Parameters for 'find' for file filtering. This dictates which files will be included in the checksum generation.
      Default is '$FIND_PARAMS'. Remember to use quotes.
  -d  Subdirectory level where to create the checksum files. 0 means the main directory set by 'directory_name'. Default is 1.
  -b  Hash binary name such as md5sum, sha1sum or sha256sum. Default is $HASH_BINARY.
  -n  File name that will contain the checksum information. Default is $CHECKSUM_FILE.
  -u  Update contents of existing checksum files. Adds new files and removes missing files. Default is to skip the directory instead.
EOF
    exit 1
}

function checksumfile_update {
    declare checksum_file="$1"
    declare find_params="$2"
    declare -i changed=0

    declare -A eligible_files
    while IFS='' read -d '' -r efile; do
        eligible_files["$efile"]=1
    done < <(find . -name "$checksum_file" -prune -o -type f $find_params -print0) || return 1

    declare -A checksumfile_files 
    while IFS='' read -r line; do
        # File name as the key and checksum as the value
        checksumfile_files["$(cut -d ',' -f 2- <<<"$line")"]="$(cut -d ',' -f 1 <<<"$line")"
    done < <(sed -n -E 's/^([^# ]+) .(.*)/\1,\2/p' "$checksum_file" 2>/dev/null) || return 1

    # Add new files
    for efile in "${!eligible_files[@]}"; do
        if [ -z "${checksumfile_files[$efile]:-}" ]; then
            "$hash_binary" "$efile" | tee -a "$checksum_file" | sed -E 's/^[^ ]+/  /' || return 1
            changed=1
        fi
    done

    # Remove missing files
    for cfile in "${!checksumfile_files[@]}"; do
        if [ -z "${eligible_files[$cfile]:-}" ]; then 
            declare cfile_escaped=$(printf '%s\n' "$cfile" | sed 's/[[\.*^$/]/\\&/g')
            sed -i'' "/^${checksumfile_files[$cfile]}..${cfile_escaped}/d" "$checksum_file" || return 1
            echo -n "    $cfile"; echo -e ": \033[1;31mDELETED\033[0m"
            changed=1
        fi
    done

    # Reset metadata
    if [ $changed -eq 1 ]; then
        sed -i'' '/^# last checked /d' "$checksum_file" || return 1
    fi
}

function checksumfile_create {
    declare hash_binary="$1"
    declare checksum_file="$2"
    declare -i dir_depth="$3"
    declare find_params="$4"
    declare -i update_existing="$5"
    declare main_dir="$6"
    declare -i errors=0

    readarray -d '' checksum_subdirs < <(find "$main_dir" -maxdepth "$dir_depth" -mindepth "$dir_depth" -type d -print0)
    echo -e "Processing directory \033[1m$main_dir\033[0m with \033[1m${#checksum_subdirs[@]}\033[0m subdirectories:"
    for workdir in "${checksum_subdirs[@]}"; do
        # Use subshell so we won't change the current working directory or environment
        (
          echo -e "  \033[1m$workdir\033[0m:"
          cd -- "$workdir" || exit 1

          if [ ! -s "$checksum_file" ]; then
              find . -name "$checksum_file" -prune -o -type f $find_params -print0 | xargs -r -0 -n1 "$hash_binary" | tee "$checksum_file" | sed -E 's/^[^ ]+/  /' || exit 1
          else
              echo -ne "    \033[1;33m$(grep -c "^[^#]" "$checksum_file")\033[0m existing checksums available. "
              if [ $update_existing -eq 1 ]; then
                  echo "Checking for new or deleted files... "
                  checksumfile_update "$checksum_file" "$find_params" || { echo -e "    \033[1;31mAn error occurred. Updating aborted.\033[0m" >&2; exit 1; }
              else
                  echo "Skipping."
              fi
          fi

        ) || ((errors += 1))
    done

    if [ $errors -eq 0 ]; then
        echo -ne "\n\033[1mCompleted without errors.\033[0m"
    else
        echo -e "\nEncountered errors with \033[1;31m$errors\033[0m checksum files!"
    fi
    return $errors
}

while getopts "uhd:b:n:f:" option; do
    case $option in
        d) DIR_DEPTH="$OPTARG";;
        b) HASH_BINARY="$OPTARG";;
        n) CHECKSUM_FILE="$OPTARG";;
        f) FIND_PARAMS="$OPTARG";;
        u) UPDATE_EXISTING=1;;
        h) _help;;
        \?) _help;;
    esac
done
shift $((OPTIND - 1))

if ! hash "$HASH_BINARY" &>/dev/null; then
    echo "Can't find required program '$HASH_BINARY'. Is it installed?"
    exit 1
fi

if [ -z "$CHECKSUM_FILE" ] || [ ! $DIR_DEPTH -ge 0 ] || [ -z "${1:-}" ]; then
    _help
fi

# Exit code will contain the total number of errors
checksumfile_create "$HASH_BINARY" "$CHECKSUM_FILE" "$DIR_DEPTH" "$FIND_PARAMS" "$UPDATE_EXISTING" "$1"

