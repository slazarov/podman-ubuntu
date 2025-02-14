#!/bin/bash

# Abort on Error
set -e

# Determine toolpath if not set already
relativepath="./" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

#curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

wget https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -O rustup-init
chmod +x rustup-init

./rustup-init
