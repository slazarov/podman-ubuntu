#!/bin/bash

get_latest_tag() {
    # Input Parameters
    # ...

    # List all Tags excluding rc Patterns
    latest=$(git tag --list --sort -tag | grep -v rc | head -n1)

    # Return Result
    echo "${latest}"
}
