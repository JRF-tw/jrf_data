#!/bin/bash

cd "$(dirname "$0")"

DATE=date
FORMAT="%Y-%m-%d"
start=`$DATE +$FORMAT -d "${1}-01-01"`
end=`$DATE +$FORMAT -d "${1}-12-31"`
now=$start
while [[ "$now" <= "$end" ]] ; do
  echo "$now"
  ./get_judgements.rb "$now"
  now=`$DATE +$FORMAT -d "$now + 1 day"`
done
