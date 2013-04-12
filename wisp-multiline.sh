#!/bin/bash
# wisp-multiline.sh --- run multiline wisp code

# Copyright (C) 2013 Arne Babenhauserheide <arne_bab@web.de>

# Author: Arne Babenhauserheide <arne_bab@web.de>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

version="wisp multiline 0.1"

# Parse commandline options

getopt -T > /dev/null
if [ $? -eq 4 ]; then
    # GNU enhanced getopt is available
    eval set -- `getopt --long help,lisp:,verbose,version,output:,interactive --options hl:vo:i -- "$@"`
else
    # Original getopt is available
    eval set -- `getopt hl:vo:i "$@"`
fi

PROGNAME=`basename $0`
ARGS=`getopt --name "$PN" --long help,lisp:,verbose,version,output:,interactive --options hl:vo:i -- "$@"`
if [ $? -ne 0 ]; then
  exit 1
fi
eval set -- $ARGS

# default options
HELP=no
LISP=guile
verbose=no
VERSION=no
OUTPUT=no
INTERACTIVE=no
wisp=""
lispcode=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)        HELP=yes;;
        -l | --lisp)        LISP="$2"; shift;;
        -o | --output)      OUTPUT="$2"; shift;;
        -v | --verbose)     VERBOSE=yes;;
        -i | --interactive) INTERACTIVE=yes;;
        --version)          VERSION=yes;;
        --)              shift; break;;
    esac
    shift
done

# Provide help output

if [[ $HELP == "yes" ]]; then
    echo "$0 [-h] [-l] [-v] [-i] [SCRIPT ...]
        Run multiline commands through wisp or execute the SCRIPT.
        
        -h | --help)        This help output.
        -l | --lisp)        Select the Lisp interpreter to call. Options: guile
        -o | --output)      Save the executed wisp code to this file.
        -v | --verbose)     Provide verbose output.
        -i | --interactive) Run interactive commands after reading scripts.
        --version)          Print the version string of this script.
"
    exit 0
fi

if [[ $VERSION == "yes" ]]; then
    echo "$version"
    exit 0
fi

# Select the lisp interpreter

if [[ $LISP != "guile" ]]; then
    echo "Interpreter $LISP not known."
    exit 1
else
    INTERPRETER="guile -s /dev/stdin"
fi

# if a script is given, execute that.

if [ $# -gt 0 ]; then
  # Remaining parameters can be processed
  for ARG in "$@"; do
      l=$(./wisp.py "${ARG}")
      lispcode="${lispcode}
${l}"
  done
  if [[ x"$INTERACTIVE" == x"no" ]]; then
      echo "${lispcode}" | ${INTERPRETER}
      exit 0
  fi
fi

# Read the code

echo ";; Welcome to wisp. Please enter your code. 
;; Finish with two linebreaks, then execute with CTRL-D."

while IFS= read wispi ; do 
    wisp="${wisp}
${wispi}" 
done 

# if the user requests output, copy the pipe with tee and append it to
# the output

if [[ x"$OUTPUT" != x"no" ]]; then
    echo "${wisp}" >> $OUTPUT
fi

# convert the input to lisp

l=$(echo "${wisp}" |  ./wisp.py - )
lispcode="${lispcode}
${l}"

# now run the code

echo "${lispcode}" | guile -s /dev/stdin
