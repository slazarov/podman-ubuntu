#!/bin/bash

get_latest_tag() {
    # Input Parameters
    # ...

    # List all Tags excluding rc Patterns
    # This seems to Fail on 1.14 being latest -> 1.9 being used e.g. on fuse-overlayfs
    # latest=$(git tag --list --sort -tag | grep -v rc | head -n1)

    # This seems to do better
    # latest=$(git tag --list --sort -creatordate | grep -v rc | head -n1)

    # Take the latest highest stable Version release
    latest=$(git tag --list --sort -creatordate | grep -v rc | grep -E ^v | sort --reverse --version-sort | head -n1)

    # Return Result
    echo "${latest}"
}

git_clone_update() {
    # Input Parameters
    local lrepository="$1"
    local lfolder="$2"

    if [ -z "${lrepository}" ] || [ -z "${lfolder}" ]
    then
        echo "FATAL: You must specify both REPOSITORY GIT URL and TARGET FOLDER"
        exit 1
    else
        if [ -d "${lfolder}" ] && [ -d "${lfolder}/.git" ]
        then
           # Git Repository has already been cloned
           # Fetch latest Changes
           git fetch --all
        else
           # Git Repository has NOT been cloned yet
           # Clone Git Repository
           git clone "${lrepository}" "${lfolder}"
        fi
    fi
}
