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

# Note that most of the error handling doesn't rely on shell opts because of the various pitfalls.
set -eu -o pipefail

# lastpipe allows "find | while read" work without subshells and helps with error handling.
set +m
shopt -s lastpipe

# Default values
declare HASH_BINARY="sha256sum"
declare CHECKSUM_FILE="SHA256SUMS"
declare -i DIR_DEPTH=0
declare -i UPDATE_EXISTING=0
# Parameters for filtering find in find-command. For example, to only include files that are over 50kiB use: -f '-size +50k'
declare FIND_PARAMS=""
declare QUIET="no"

declare C_WHITE=$(printf "\033[1m")
declare C_GREEN=$(printf "\033[1;32m")
declare C_RED=$(printf "\033[1;31m")
declare C_END=$(printf "\033[0m")

function _help {
    cat << EOF

Usage: $0 [-b hash_binary_name] [-d subdir_depth] [-f "find_params"] [-n checksum_file_name] [-u] directory_name

Recursively creates checksum files using $HASH_BINARY. Option -d will define the subdirectory level
on which the files are created (default is 0 which means current directory). The checksum file will contain checksums of files in and under that directory.
Integrity verification can be done directly with sha256sum or by using $(echo -e "${C_WHITE}checksumfile-verify.sh${C_END}").

Options:
  -f  Parameters for 'find' for file filtering. This dictates which files will be included in the checksum generation.
      Default is '$FIND_PARAMS'. Remember to use quotes.
  -d  Subdirectory level where to create the checksum files. 0 means the main directory set by 'directory_name'. Default is $DIR_DEPTH.
  -b  Hash binary name such as md5sum, sha1sum or sha256sum. Default is $HASH_BINARY.
  -n  File name that will contain the checksum information. Default is $CHECKSUM_FILE.
  -q  Quiet mode. Only print file names that couldn't be created or updated.
  -u  Update contents of existing checksum files. Adds new files and removes missing files. Default is to skip the directory instead.
EOF
    exit 1
}

function find_wrapper {
    eval 'find . -name "$1" -prune -o -type f '$2' -print0' || return 1
}

function checksumfile_update {
    declare hash_binary="$1"
    declare checksum_file="$2"
    declare find_params="$3"
    declare -i changed=0

    # Find files that should be hashed.
    declare -A eligible_files
    find_wrapper "$checksum_file" "$find_params" | while IFS='' read -d '' -r efile; do
        eligible_files["$efile"]=1
    done || return 1

    # Gather already hashed files to an associative array.
    declare -A checksumfile_files 
    sed -n -E 's/^([^# ]+) .(.*)/\1,\2/p' "$checksum_file" 2>/dev/null | while IFS='' read -r line; do
        # File name as the key and checksum as the value
        checksumfile_files["$(cut -d ',' -f 2- <<<"$line")"]="$(cut -d ',' -f 1 <<<"$line")"
    done || return 1

    # Add new files that are not hashed already.
    for efile in "${!eligible_files[@]}"; do
        if [ -z "${checksumfile_files[$efile]:-}" ]; then
            "$hash_binary" "$efile" | tee -a "$checksum_file" | sed -E "s/^[^ ]+/$(printf "    ${C_GREEN}Added${C_END}")/" || return 1
            changed=1
        fi
    done

    # Remove missing files.
    for cfile in "${!checksumfile_files[@]}"; do
        if [ -z "${eligible_files[$cfile]:-}" ]; then 
            declare cfile_escaped=$(printf '%s\n' "$cfile" | sed 's/[[\.*^$/]/\\&/g')
            sed -i'' "/^${checksumfile_files[$cfile]}..${cfile_escaped}/d" "$checksum_file" || return 1
            echo -ne "    ${C_RED}Deleted${C_END} " ; echo "$cfile"
            changed=1
        fi
    done

    # Reset verification metadata.
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
    echo -e "Processing directory ${C_WHITE}$main_dir${C_END} with ${C_WHITE}${#checksum_subdirs[@]}${C_END} subdirectories:"
    for workdir in "${checksum_subdirs[@]}"; do
        # Use subshell so we won't change the current working directory or environment
        (
          echo -e "  ${C_WHITE}$workdir${C_END}:"
          cd -- "$workdir" 2>&1 || exit 1

          if [ ! -s "$checksum_file" ]; then
              find_wrapper "$checksum_file" "$find_params" | xargs -r -0 -n1 "$hash_binary" | tee "$checksum_file" | sed -E 's/^[^ ]+/  /' || exit 1
          else
              echo -ne "    \033[1;33m$(grep -c "^[^#]" "$checksum_file")${C_END} existing checksums available. "
              if [ $update_existing -eq 1 ]; then
                  echo "Checking for new or deleted files... "
                  checksumfile_update "$hash_binary" "$checksum_file" "$find_params" || { echo -e "    ${C_RED}An error occurred. Updating aborted.${C_END}"; exit 1; }
              else
                  echo "Skipping."
              fi
          fi

        ) || {
            [ "$QUIET" == "yes" ] && echo "$(readlink -f "$checksum_file")" >&2
            ((errors += 1))
        }
    done

    if [ $errors -eq 0 ]; then
        echo -e "\n${C_WHITE}Completed without errors.${C_END}"
        return 0
    else
        echo -e "\nEncountered errors with ${C_RED}$errors${C_END} checksum files!"
        return 2
    fi
}

while getopts "quhd:b:n:f:" option; do
    case $option in
        d) DIR_DEPTH="$OPTARG";;
        b) HASH_BINARY="$OPTARG";;
        n) CHECKSUM_FILE="$OPTARG";;
        f) FIND_PARAMS="$OPTARG";;
        u) UPDATE_EXISTING=1;;
        q) QUIET="yes";;
        h) _help;;
        \?) _help;;
    esac
done
shift $((OPTIND - 1))

if ! hash "$HASH_BINARY" &>/dev/null; then
    echo "Can't find required program '$HASH_BINARY'. Is it installed?"
    exit 1
fi

if [ -z "$CHECKSUM_FILE" ] || [ ! $DIR_DEPTH -ge 0 ]; then
    _help
fi


if [ "$QUIET" == "no" ]; then
    # Exit code 1 is for critical runtime errors and 2 for non-critical errors with checksum files.
    checksumfile_create "$HASH_BINARY" "$CHECKSUM_FILE" "$DIR_DEPTH" "$FIND_PARAMS" "$UPDATE_EXISTING" "${1:-.}"
else
    checksumfile_create "$HASH_BINARY" "$CHECKSUM_FILE" "$DIR_DEPTH" "$FIND_PARAMS" "$UPDATE_EXISTING" "${1:-.}" 2>&1 >/dev/null
fi
