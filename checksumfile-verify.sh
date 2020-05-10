#!/usr/bin/env bash
# Copyright (C) 2020 kalaksi@users.noreply.github.com
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

set -eu

# Default options 
declare HASH_BINARY="sha256sum"
declare CHECKSUM_FILE="SHA256SUMS"
declare -i VERIFY_PERCENTAGE=100

function _help {
    cat << EOF

Usage: $0 [-b hash_binary_name] [-n checksum_file_name] [-p verify_percentage] directory_name

Verifies the integrity of files described using the common format in the file $CHECKSUM_FILE.
Can process multiple checksum files and records metadata about the check time and failure
count in the file.

Options:
  -h  Hash binary name such as md5sum, sha1sum or sha256sum. Default is $HASH_BINARY.
  -n  File name that will contain the checksum information. Default is $CHECKSUM_FILE.
  -p  Percentage of checksum files to process. E.g. "5" will mean that about 5% of the available
      checksum files will be processed. The file with the oldest check timestamp will be processed
      first. This means that it would take 20 days to go through all files. Default is $VERIFY_PERCENTAGE.
EOF
    exit 1
}

function get_check_metadata {
    declare metadata;
    metadata="$(sed -n -E '1 s/^# last checked ([0-9]+-[0-9]+-[0-9]+_[0-9]+:[0-9]+:[0-9]+) with ([0-9]+) failures/\1,\2/p' "$1" 2>/dev/null)" || return 1
    if [ -z "$metadata" ]; then
        printf "0000-00-00_00:00:00,0"
    else
        printf "$metadata"
    fi
}

function set_check_metadata {
    # Metadata is meant to be human readable so that it's possible to use the data without these tools.
    declare checksum_file="$1"
    declare -i failures="$2"
    declare old_metadata; old_metadata=$(get_check_metadata "$checksum_file") || return 1
    declare new_metadata="# last checked $(date +"%Y-%m-%d_%H:%M:%S") with $failures failures"

    # Metadata doesn't exist yet
    if [[ ${old_metadata:0:4} == "0000" ]]; then
        sed -i'' "1 i $new_metadata" "$checksum_file"
    else
        sed -i'' "1 s/^# last checked.*/$new_metadata/" "$checksum_file"
    fi
}

function list_checksumfiles_ordered {
    readarray -d '' files < <(find "$1" -type f -size +32c -name "$2" -print0)
    # Sort the files by last check time. Oldest first.
    readarray -d '' sorted_indices < <(
      ( for i in "${!files[@]}"; do
            metadata="$(get_check_metadata "${files[$i]}")" || { echo "Can't read checksum file '${files[$i]}'" >&2; continue; }
            printf "%s,%s\0" "$i" "$metadata"
        done ) | sort -t ',' -k 2 -z | cut -d ',' -f 1 -z
    )

    for i in "${sorted_indices[@]}"; do
        printf "%s\0" "${files[$i]}"
    done
}

function checksumfile_verify {
    declare hash_binary="$1"
    declare checksum_file="$2"
    declare -i verify_percentage="$3"
    declare main_dir="$4"
    # Note: checksum files that can't be accessed will be left out from the check
    readarray -d '' checksum_files < <(list_checksumfiles_ordered "$main_dir" "$checksum_file")
    declare -i errors_total=0
    declare -i checksums_checked=0
    declare -i checksums_total="$(printf "%s\0" "${checksum_files[@]}" | xargs -n1 -r -0 grep '^[^#]' | wc -l)"
    echo -e "\nProcessing directory \033[1m${main_dir}\033[0m containing \033[1;32m${#checksum_files[@]}\033[0m available checksum files:"

    for f in "${checksum_files[@]}"; do
        declare -i checksum_errors=0

        declare workdir=$(dirname "$f")
        pushd -- "$workdir" &>/dev/null
        echo -e "  \033[1m${workdir}\033[0m:"

        # Go through one by one for better view on progress and error counting
        while IFS='' read -r line; do
            (
              set -o pipefail
              # Apply some colors too depending on the output
              "$hash_binary" --strict -c 2>/dev/null <<<"$line" | \
              sed -e 's/^/    /' \
                  -e "s/OK/$(printf "\033[1;32mOK\033[0m/")" \
                  -e "s/FAILED/$(printf "\033[1;31mFAILED\033[0m/")"
            ) || ((checksum_errors += 1))
            ((checksums_checked += 1))

        # Trim out comment lines
        done < <(grep '^[^#]' "$checksum_file")

        set_check_metadata "$checksum_file" "$checksum_errors" || ((errors_total += 1))
        errors_total=$((errors_total + $checksum_errors))
        popd &>/dev/null

        if [ $(( 100 * $checksums_checked / $checksums_total )) -ge $verify_percentage ]; then
            echo -ne "\nReached target percentage ${verify_percentage}% of checked checksums."
            break
        fi
    done

    echo -e "\n\033[1m${checksums_checked}/${checksums_total}\033[0m checksums checked. \033[1m${errors_total}\033[0m errors found!"
    return $errors_total
}


while getopts "hb:n:p:" option; do
    case $option in
        b) HASH_BINARY="$OPTARG";;
        n) CHECKSUM_FILE="$OPTARG";;
        p) VERIFY_PERCENTAGE="$OPTARG";;
        h) _help;;
        \?) _help;;
    esac
done
shift $((OPTIND - 1))

if ! hash "$HASH_BINARY" &>/dev/null; then
    echo "Can't find required program '$HASH_BINARY'. Is it installed?"
    exit 1
fi

if [ -z "$CHECKSUM_FILE" ] || [ -z "${1:-}" ]; then
    _help
fi

# Exit code will contain the total number of errors
checksumfile_verify "$HASH_BINARY" "$CHECKSUM_FILE" "$VERIFY_PERCENTAGE" "$1"
