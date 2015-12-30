#!/bin/bash
# set -o xtrace

cd "$(dirname "$0")"

DATE=date
FORMAT="%Y-%m-%d"
VAR=$1
SIZE=${#VAR}
if [ $SIZE -eq 10 ]; then
  YEAR=`echo $VAR | cut -d '-' -f 1`
  start=`$DATE +$FORMAT -d "${VAR}"`
  end=`$DATE +$FORMAT -d "${YEAR}-12-31 + 1 day"`
else
  start=`$DATE +$FORMAT -d "${VAR}-01-01"`
  end=`$DATE +$FORMAT -d "${VAR}-12-31 + 1 day"`
  YEAR=$VAR
fi

now=$start
echo "start get judgements..." > log/get_judgements-${YEAR}.log
while [[ "$now" < "$end" ]] ; do
  echo "$now"
  ./get_judgements.rb "$now" >> log/get_judgements-${YEAR}.log 2>&1
  now=`$DATE +$FORMAT -d "$now + 1 day"`
done
