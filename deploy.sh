#!/bin/bash

# Copyright (c) 2014 Moritz Schepp <moritz.schepp@gmail.com>
# Distributed under the GNU GPL v3. For full terms see
# http://www.gnu.org/licenses/gpl-3.0.txt

# This is a deploy script for generic apps. Modify the deploy function to suit
# your needs.

# Load user settings

. ./deploy.config.sh && $1

# Deploy

function deploy {
  setup

  within_do $OLD_CURRENT_PATH "RAILS_ENV=production bundle exec script/delayed_job stop || true"

  deploy_code
  cleanup

  within_do $CURRENT_PATH "bundle --deployment --without test development --path $SHARED_PATH/bundle"

  remote "ln -sfn $SHARED_PATH/database.yml $CURRENT_PATH/config/database.yml"
  remote "ln -sfn $SHARED_PATH/contact.txt $CURRENT_PATH/config/contact.txt"
  remote "ln -sfn $SHARED_PATH/help.yml $CURRENT_PATH/config/help.yml"
  remote "ln -sfn $SHARED_PATH/legal.txt $CURRENT_PATH/config/legal.txt"
  remote "ln -sfn $SHARED_PATH/log $CURRENT_PATH/log"
  remote "ln -sfn $SHARED_PATH/tmp $CURRENT_PATH/tmp"
  remote "ln -sfn $SHARED_PATH/data $CURRENT_PATH/data"
  remote "ln -sfn $SHARED_PATH/kor.yml $CURRENT_PATH/config/kor.yml"
  remote "ln -sfn $SHARED_PATH/kor.app.yml $CURRENT_PATH/config/kor.app.yml"

  within_do $CURRENT_PATH "RAILS_ENV=production bundle exec rake db:migrate"
  within_do $CURRENT_PATH "RAILS_ENV=production bundle exec rake assets:precompile"
  within_do $CURRENT_PATH "RAILS_ENV=production bundle exec script/delayed_job start"

  remote "mkdir -p $CURRENT_PATH/public/media/images"
  remote "ln -sfn $SHARED_PATH/data/media/preview $CURRENT_PATH/public/media/images/preview"
  remote "ln -sfn $SHARED_PATH/data/media/thumbnail $CURRENT_PATH/public/media/images/thumbnail"
  remote "ln -sfn $SHARED_PATH/data/media/icon $CURRENT_PATH/public/media/images/icon"

  remote "touch $CURRENT_PATH/tmp/restart.txt"

  finalize
}


# Variables

TIMESTAMP=`date +"%Y%m%d%H%M%S"`
CURRENT_PATH="$DEPLOY_TO/releases/$TIMESTAMP"
SHARED_PATH="$DEPLOY_TO/shared"
OLD_CURRENT_PATH="$DEPLOY_TO/current"
REVISION=`git rev-parse $COMMIT`

RED="\e[0;31m"
GREEN="\e[0;32m"
BLUE="\e[0;34m"
LIGHTBLUE="\e[1;34m"
NOCOLOR="\e[0m"


# Generic functions

function within_do {
  remote "cd $1 ; $2"
}

function remote {
  echo -e "${BLUE}$HOST${NOCOLOR}: ${LIGHTBLUE}$1${NOCOLOR}" 1>&2
  ssh $HOST -p $PORT "bash -c \"$1\""
  STATUS=$?

  if [[ $STATUS != 0 ]] ; then
    echo -e "${RED}deployment failed with status code $STATUS${NOCOLOR}"
    exit $STATUS
  fi
}

function local {
  echo -e "${BLUE}locally${NOCOLOR}: ${LIGHTBLUE}$1${NOCOLOR}" 1>&2
  bash -c "$1"
  STATUS=$?

  if [[ $STATUS != 0 ]] ; then
    echo -e "${RED}deployment failed with status code $STATUS${NOCOLOR}"
    exit $STATUS
  fi
}

function setup {
  remote "mkdir -p $DEPLOY_TO/shared"
  remote "mkdir -p $DEPLOY_TO/releases"
}

function deploy_code {
  local "git archive --format=tar $COMMIT | gzip > deploy.tar.gz"
  local "scp -P $PORT deploy.tar.gz $HOST:$DEPLOY_TO/deploy.tar.gz"
  local "rm deploy.tar.gz"

  remote "mkdir $CURRENT_PATH"
  within_do $CURRENT_PATH "tar xzf ../../deploy.tar.gz"
  remote "echo $REVISION > $CURRENT_PATH/REVISION"
  remote "rm $DEPLOY_TO/deploy.tar.gz"
  remote "ln -sfn $CURRENT_PATH $DEPLOY_TO/current"
}

function cleanup {
  EXPIRED=`remote "(ls -t $DEPLOY_TO/releases | head -n $KEEP ; ls $DEPLOY_TO/releases) | sort | uniq -u | xargs"`
  for d in $EXPIRED ; do
    remote "rm -rf $DEPLOY_TO/releases/$d"
  done
}

function finalize {
  echo -e "${GREEN}deployment successful${NOCOLOR}"
}


# Main

deploy
