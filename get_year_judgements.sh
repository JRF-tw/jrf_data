#!/bin/bash

cd "$(dirname "$0")"

DATE=date
FORMAT="%Y-%m-%d"
start=`$DATE +$FORMAT -d "${1}-01-01"`
end=`$DATE +$FORMAT -d "${1}-12-31 + 1 day"`
now=$start
echo "start get judgements..." > log/get_judgements-${1}.log
while [[ "$now" < "$end" ]] ; do
  echo "$now"
  ./get_judgements.rb "$now" >> log/get_judgements-${1}.log 2>&1
  now=`$DATE +$FORMAT -d "$now + 1 day"`
done
