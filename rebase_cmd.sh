 #!/bin/bash

# Usage
function usage()
{
  echo "rebase.sh : utility to run a command on another machine"
  echo "usage:"
  echo "  rebase.sh [options] -- <command> [args]"
  echo "options:"
  echo "  -d <dir>     : Copy all local file arguments to _dir_"
  exit 255
}

# Must have arguments
if [[ $# -lt 1 ]]; then usage; fi

# Read arguments
COPYDIR=
while getopts ":hd:-" opt; do
  case $opt in 
    h )
      usage
      ;;
    d )
      COPYDIR=$OPTARG
      ;;
    - )
      break
      ;;
    \? )
      echo "Unknown option: $OPTARG" 1>&2
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      ;;
  esac
done

# Shift the arguments
shift $((OPTIND -1))

# Make sure there is a target directory
if [[ ! $COPYDIR ]]; then
  COPYDIR=$(mktemp -d -t rebase-XXXXXX)
else
  mkdir -p $COPYDIR
fi

# Tell user where we are rebasing to
echo "Rebasing to: $(readlink -f $COPYDIR)"

# Parse the remaining command
F_SRC=()
F_DST=()
REBASED=""

for arg in "$@"; do
  if [[ -f $arg ]]; then
    F_SRC+=($arg)
    F_NEW=$(basename $arg)
    F_TRY=$F_NEW
    N_TRY=0
    while [[ -f $F_TRY ]]; do
      F_TRY="$F_NEW.${N_TRY}"
      N_TRY=$((N_TRY+1))
    done
    F_DST+=($F_TRY)
    REBASED="$REBASED $F_TRY"

    # don't copy the command
    if [[ $arg != $1 ]]; then
      cp -aL $arg "$COPYDIR/$F_TRY"
    fi
  else
    REBASED="$REBASED $arg"
  fi
done

# Print the rebased command
echo "Command: $REBASED"
