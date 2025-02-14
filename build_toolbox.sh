#!/bin/bash

# Abort on Error
# set -e

# Determine toolpath if not set already
relativepath="./" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Change Folder to Build Root
cd "${BUILD_ROOT}" || exit

# Might actually not be needed for build-only (more for Troubleshooting)
# go install golang.org/x/tools/gopls@latest

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/containers/toolbox.git
cd toolbox

if [[ -n "${TOOLBOX_TAG}" ]]
then
   git checkout "${TOOLBOX_TAG}"
else
   git checkout $(get_latest_tag)
fi

# Change into "src" Subfolder
cd src || exit

# Must Patch 1.22.6 -> 1.23 in /usr/src/podman/podman/go.mod
sed -Ei "s|^go 1.22.6$|go 1.23|" go.mod

# Build using Meson
#meson setup builddir && cd builddir
#meson compile
#meson test

meson --prefix /usr --buildtype=plain builddir
cd buildir || exit
meson compile -C builddir
meson test -C builddir
DESTDIR=/usr/local meson install -C builddir


# Copy to Target Folder

