GITHUB_DIR=$(dirname $(pwd))
export PATH_TO_PLUGIN=`dirname ${GITHUB_DIR}`
export TESTSPACE_NAME=testspace
export TESTSPACE=$PATH_TO_PLUGIN/$TESTSPACE_NAME
export PATH_TO_REDMINE=$TESTSPACE/redmine
export RAILS_ENV=test
