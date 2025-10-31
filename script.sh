#!/bin/bash
# Place in project's base directory, then run from there.

PDIR=`pwd` # project base dir
# Space-separated replacement items. Each line consists of: {Key} {StringToFind} {ReplacementString}
REPS=(
  "log.verbose{}"
)
for FILE in `ls "$PDIR"/iina/*.lproj/Localizable.strings`
do
  for REP in "${REPS[@]}"
  do
    TOKENS=($REP) # Break line into tokens by spaces
    sed -i '' 's/\("'"${TOKENS[0]}"'".*\)\('${TOKENS[1]}'\)\(.*\)/\1'${TOKENS[2]}'\3/' "$FILE"
  done
done
