#!/bin/bash
# Place in project's base directory, then run from there.

PDIR=`pwd` # project base dir
for FILE in `ls "$PDIR"/iina/*.swift`
do
  sed -i '' 's/\(\s*\)log.error{\(.*\)}/\1log.error(\2)/' $FILE
done
