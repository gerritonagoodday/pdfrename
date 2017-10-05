#!/bin/bash

PROGNAME=${0##*/}
STARTTIME=$(date +%s)

function Usage {
  printf "
Usage:
  ${0##*/} filepath.pdf \"Document title to be set\"
    or
  ${0##*/} filepath.pdf
    or
  ${0##*/} filepath.pdf -e \"[regex search pattern in system filename]\" \"[regex substitution pattern]\"


Function:
  Use this utility to rename the internal name of a PDF file without having to
  edit the file with a bespoke PDF editor, and without modifying the system file
  name either.


Example:
	${0##*/} ebook.pdf \"My very first little eBook\"

	 - sets the PDF Document Title to \"My very first little eBook\"

  ${0##*/} ebook.pdf -e \"\(.*\)\" \"\\1 - Annotated copy\"

   - sets the PDF Document Title to \"ebook - Annotated copy\"

Author:
  Gerrit Hoekstra. You can contact me via https://github.com/gerritonagoodday
"
  exit 1
}

function die {
  if [[ -z $1 ]]; then
    printf "$(tput setaf 9)failed.\nExiting...\n$(tput sgr 0)"
  else
    printf "$(tput setaf 9)*** $1 ***\nExiting...\n$(tput sgr 0)"
  fi
  exit 1
}
function warn {
  printf "$(tput setaf 3)Warning: $1\n$(tput sgr 0)"
}
function info {
  printf "$(tput setaf 10)$1...\n$(tput sgr 0)"
}
function doneit {
  if [[ -n $1 ]]; then
    printf "$(tput setaf 12)$1, done\n$(tput sgr 0)"
  else
    printf "$(tput setaf 12)done\n$(tput sgr 0)"
  fi
}

PDFFILE="${1}"
[[ -z $PDFFILE ]] && Usage
shift
if [[ "$1" == "-e" ]]; then
  # A regular expression is expected in the net parameter.
  # Turn off globbing
  set -f
  shift
  regex=true
  # Check if expression fields were specified
  [[ -z $1 ]] && Usage
  [[ -z $2 ]] && Usage
  # Use remaining text from the command line as a regex against the file title
  BASEFILENAME=${PDFFILE##*/}
  TITLE=$( echo ${BASEFILENAME%%\.pdf} | sed -e "s/$1/$2/" )
else
  if [[ -z $1 ]]; then
    # Use the file system name as the document title+
    BASEFILENAME=${PDFFILE##*/}
    TITLE=${BASEFILENAME%%\.pdf}
  else
    # Use remaining text from the command line as Document title
    TITLE=$1
  fi
fi
info "Setting the document title to '$TITLE'"

# Temp work files
TMPFILE1=$(mktemp "/tmp/tmp.${PROGNAME}.$$.XXXXXX")
TMPFILE2=$(mktemp "/tmp/tmp.${PROGNAME}.$$.XXXXXX")

#============================================================================#
# Set traps and signal BEGIN and END
# Need logging to work for this
#============================================================================#
function cleanup {
  rm "${TMPFILE1}" 2>/dev/null
  rm "${TMPFILE2}" 2>/dev/null
  ENDTIME=$(date +%s)
  elapsedseconds=$((ENDTIME-STARTTIME))
  s=$((elapsedseconds % 60))
  m=$(((elapsedseconds / 60) % 60))
  h=$(((elapsedseconds / 60 / 60) % 24))
  duration=$(printf "Duration (h:m:s): %02d:%02d:%02d" $h $m $s)
  doneit "${duration}"
  exit
}
for sig in KILL TERM INT EXIT; do trap 'cleanup $sig' "$sig" ; done

info "Checking environment"
PDFTK=`which pdftk 2>/dev/null`
[[ -z "$PDFTK" ]] && die "pdftk does not appear to be installed."
info "Checking $PDFFILE"
[[ ! -f $PDFFILE ]] && die "$PDFFILE does not exist"
filetype=$(file -b "$PDFFILE")
if [[ $filetype =~ ^PDF ]]; then
  info "$PDFFILE is a PDF file"
else
  die "File $PDFFILE does not appear to be a PDF file."
fi

info "Dumping metadata of $PDFFILE"
pdftk "$PDFFILE" dump_data output $TMPFILE1 > /dev/null 2>&1
retcode=$?
[[ $retcode -ne 0 ]] && die "pdftk returned error code $retcode"

info "Fixing metadata for $PDFFILE"
# Remove 2 info strings
sed -i $TMPFILE1 -e '/InfoKey:\s*Title/,+1d'
if [[ -n $(grep -i -e "InfoKey:\s*Title" $TMPFILE1) ]]; then
  die "Failed to remove 'InfoKey: Title' from metadata file"
fi
# Title is not set in the Document any more - add it to the beginning of all metadata
echo "InfoValue: $TITLE" | cat - $TMPFILE1 | tee $TMPFILE1 > /dev/null
echo "InfoKey: Title" | cat - $TMPFILE1 | tee $TMPFILE1 > /dev/null

info "Reloading metadata"
pdftk "$PDFFILE" update_info $TMPFILE1 output $TMPFILE2  > /dev/null 2>&1
[[ $? -ne 0 ]] && die "Could not update PDF metadata for source file '$PDFFILE'"
mv $TMPFILE2 "$PDFFILE"
[[ $? -ne 0 ]] && die "Could not write PDF metadata into source file '$PDFFILE'"
doneit
