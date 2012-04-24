#!/bin/bash
# Installer for GitLab on RHEL 6 (Red Hat Enterprise Linux and CentOS)

die()
{
  # $1 - the exit code
  # $2 $... - the message string

  retcode=$1
  shift
  printf >&2 "%s\n" "$@"
  exit $retcode
}
