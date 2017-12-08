#!/bin/bash -e

DIR=~/home/docker/awuersch/python
replica=('ds1' 'ds2' 'ds3')

for cid in ${replica[@]}
do
  $DIR/run-elect.sh $cid
done
