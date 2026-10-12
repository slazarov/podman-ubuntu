#!/bin/bash
# package_revision.sh — the packaging revision N in ~ubuntu{VERSION_ID}.podmanN.
#
# Single source of truth, sourced by config.sh (build) and
# check_republish_needed.sh (republish guard) so the two cannot drift.
#
# BUMP THIS whenever packaging changes (Depends, Conflicts, file paths, renames)
# without an upstream version change. Otherwise the rebuilt .debs carry the
# exact version string already published: apt never upgrades to an identical
# version, and ci_publish.sh's pool-immutability rule adopts the already-
# published .deb of the same filename, silently discarding the new build.
# The bump changes every package's filename once, so the whole set republishes.
#
# History: 1 = initial; 2 = uidmap dep, helpers in /usr/libexec/podman,
# containers-image conflict, tmpfiles, podman-toolbox -> podman-toolbx.
export PACKAGE_REVISION="${PACKAGE_REVISION:-2}"
