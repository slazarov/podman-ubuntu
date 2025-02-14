#!/bin/bash

get_latest_tag() {
    # Input Parameters
    # ...

    # List all Tags excluding rc Patterns
    # This seems to Fail on 1.14 being latest -> 1.9 being used e.g. on fuse-overlayfs
    # latest=$(git tag --list --sort -tag | grep -v rc | head -n1)

    # This seems to do better
    latest=$(git tag --list --sort -creatordate | grep -v rc | head -n1)

    # Return Result
    echo "${latest}"
}
