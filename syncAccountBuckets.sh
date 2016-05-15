#!/bin/bash

function usage() {
  echo -e "\nSynchronise the contents of the code and credentials buckets to the local values" 
  echo -e "\nUsage: $(basename $0) -a OAID -d DOMAIN -x -y"
  echo -e "\nwhere\n"
  echo -e "(m) -a OAID is the organisation account id e.g. \"env01\""
  echo -e "(o) -d DOMAIN is the domain of the buckets to be synchronised"
  echo -e "    -h shows this text"
  echo -e "(o) -x for no delete - by default files in the buckets that are absent locally are deleted"
  echo -e "(o) -y for a dryrun - show what will happen without actually transferring any files"
  echo -e "\nDEFAULTS:\n"
  echo -e "DOMAIN = {OAID}.gosource.com.au"
  echo -e "\nNOTES:\n"
  echo -e "1) The OAID is only used to ensure we are in the OAID directory"
  echo -e ""
  exit 1
}

DRYRUN=
DELETE="--delete"

# Parse options
while getopts ":a:d:hy" opt; do
  case $opt in
    a)
      OAID=$OPTARG
      ;;
    d)
      DOMAIN=$OPTARG
      ;;
    h)
      usage
      ;;
    x)
      DELETE=
      ;;
    y)
      DRYRUN="--dryrun"
      ;;
    \?)
      echo -e "\nInvalid option: -$OPTARG" 
      usage
      ;;
    :)
      echo -e "\nOption -$OPTARG requires an argument" 
      usage
      ;;
   esac
done


# Ensure mandatory arguments have been provided
if [[ "${OAID}" == "" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ROOT_DIR="$(pwd)"
ROOT="$(basename ${ROOT_DIR})"

STARTUP_DIR="${ROOT_DIR}/infrastructure/startup"

ACCOUNT_DIR="${ROOT_DIR}/config/${OAID}"
ACCOUNT_CREDS_DIR="${ROOT_DIR}/infrastructure/${OAID}/credentials"

SOLUTIONS_DIR="${ROOT_DIR}/config/solutions"


if [[ "${OAID}" != "${ROOT}" ]]; then
    echo -e "\nThe provided OAID (${OAID}) doesn't match the root directory (${ROOT}). Nothing to do."
    usage
fi

# Set the profile if on PC to pick up the IAM credentials to use to access the credentials bucket. 
# For other platforms, assume the server has a service role providing access.
uname | grep -iE "MINGW64|Darwin|FreeBSD" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
    PROFILE="--profile ${OAID}"
fi

pushd ${ACCOUNT_DIR}  > /dev/null 2>&1

REGION=$(grep '"Region"' account.json | cut -d '"' -f 4)

if [[ "${REGION}" == "" ]]; then
    echo -e "\nThe region must be defined in the account configuration file. Are we in the correct directory? Nothing to do."
    usage
fi

if [[ "${DOMAIN}" == "" ]]; then DOMAIN=${OAID}.gosource.com.au; fi

# Confirm access to the code bucket
aws ${PROFILE} --region ${REGION} s3 ls s3://code.${DOMAIN}/ > /dev/null 2>&1
if [[ "$?" -ne 0 ]]; then
      echo -e "\nCan't access the code bucket. Does the service role for the server include access to the \"${OAID}\" configuration bucket? If windows, is a profile matching the account been set up? Nothing to do."
      usage
fi

cd ${STARTUP_DIR}
aws ${PROFILE} --region ${REGION} s3 sync ${DRYRUN} ${DELETE} --exclude=".git*" bootstrap/ s3://code.${DOMAIN}/bootstrap/

# Confirm access to the credentials bucket
aws ${PROFILE} --region ${REGION} s3 ls s3://credentials.${DOMAIN}/ > /dev/null 2>&1
if [[ "$?" -ne 0 ]]; then
      echo -e "\nCan't access the credentials bucket. Does the service role for the server include access to the \"${OAID}\" configuration bucket? If windows, is a profile matching the account been set up? Nothing to do."
      usage
fi

cd ${ACCOUNT_CREDS_DIR}/alm/docker
aws ${PROFILE} --region ${REGION} s3 sync ${DRYRUN} ${DELETE} . s3://credentials.${DOMAIN}/${OAID}/alm/docker/

