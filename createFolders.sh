#!/bin/bash
[ ! -d "./perfReports" ] && mkdir ./perfReports
[ ! -d "./src" ] && mkdir ./src
[ ! -d "./data" ] && mkdir ./data
export $(grep -v '^#' .env | xargs -0)
# echo $(env)