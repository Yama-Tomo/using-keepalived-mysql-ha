#!/bin/bash

############################### setting ##############################

export LANG=C

WHICH='/usr/bin/which'
MYSQL=$($WHICH mysql)
GREP=$($WHICH grep)
SED=$($WHICH sed)
SLEEP=$($WHICH sleep)
AWK=$($WHICH awk)
WC=$($WHICH wc)

USER=${1:-root}
PASSWORD=${2:-password}
LOG=${3:-/var/log/mysql_failover.log}


############################### function ##############################

function isSlave() {
  local user=$1
  local password=$2

  local result=$($MYSQL -u$user -p$password -e "SHOW SLAVE STATUS" | $GREP "[^-+]" | $SED "1d;3d" | $AWK -F'\t' '{print $11,$12}')

  local Slave_IO_Running=$(echo $result | $AWK -F' ' '{print $1}')
  local Slave_SQL_Running=$(echo $result | $AWK -F' ' '{print $2}')

  if [ "$Slave_IO_Running" = "Yes" -a "$Slave_SQL_Running" = "Yes" ]; then
    # this server slave databse.
    return 0
  else
    logger "INFO" "This server not slave database. Migration cancel" $LOG
    return 1
  fi
}

function isPromote() {
  local user=$1
  local password=$2

  local result=$($MYSQL -u$user -p$password -e "SHOW SLAVE STATUS" | $GREP "[^-+]" | $SED "1d;3d" | $AWK -F'\t' '{print $7,$22}')

  local Read_Master_Log_Pos=$(echo $result | $AWK -F' ' '{print $1}')
  local Exec_Master_Log_Pos=$(echo $result | $AWK -F' ' '{print $2}')

  if [ "$Read_Master_Log_Pos" = "" ]; then
    logger "ERROR" "Read_Master_Log_Pos is null!" $LOG
    return 1
  fi

  if [ "$Exec_Master_Log_Pos" = "" ]; then
    logger "ERROR" "Exec_Master_Log_Pos is null!" $LOG
    return 2
  fi

  if [ "$Read_Master_Log_Pos" != "$Exec_Master_Log_Pos" ]; then
    return 3
  fi

  if [ "$Read_Master_Log_Pos" = "$Exec_Master_Log_Pos" ]; then
    return 0
  fi
}

function setupMaster() {
  local user=$1
  local password=$2

  local message=$($MYSQL -u$user -p$password -e "STOP SLAVE" 2>&1)
  if [ $? -ne 0 ]; then
    logger "ERROR" "Failed STOP SLAVE" $LOG
    return 1
  fi

  message=$($MYSQL -u$user -p$password -e "RESET SLAVE" 2>&1)
  if [ $? -ne 0 ]; then
    logger "ERROR" "Failed RESET SLAVE" $LOG
    return 2
  fi

  message=$($MYSQL -u$user -p$password -e "RESET MASTER" 2>&1)
  if [ $? -ne 0 ]; then
    logger "ERROR" "Failed RESET MASTER" $LOG
    return 3
  fi

  message=$($MYSQL -u$user -p$password -e "SET GLOBAL rpl_semi_sync_slave_enabled = 0" 2>&1)
  if [ $? -ne 0 ]; then
    logger "ERROR" "Failed SET GLOBAL rpl_semi_sync_slave_enabled = 0" $LOG
    return 4
  fi

  message=$($MYSQL -u$user -p$password -e "SET GLOBAL read_only = 0" 2>&1)
  if [ $? -ne 0 ]; then
    logger "ERROR" "Failed SET GLOBAL read_only = 0" $LOG
    return 5
  fi

  return 0
}

function logger() {
  local level=$1
  local message=$2
  local log_path=$3

  echo "$(/bin/date +'%b %d %k:%M:%S') $(/bin/hostname) [$level] : $message " >> $log_path
}


############################### main ##############################

logger "INFO" "Migration master database. Start" $LOG

## step1  Check slave database?
isSlave $USER $PASSWORD

if [ $? -ne 0 ]; then
  exit 0
fi

## step2  Waiting unapplied relaylog query.
i=0
while :
do
  isPromote $USER $PASSWORD
  result=$?

  # RelayLog execute done.
  if [ $result -eq 0 ]; then
    break
  fi

  # RelayLog execute running.
  if [ $result -eq 3 ]; then
    $SLEEP 0.5
    i=$((i+1))
    logger "INFO" "waiting relaylog execute complete. [$i]" $LOG
    continue
  fi

  # critical error.
  exit $?
done

## step3  Setup Master database.
setupMaster $USER $PASSWORD
  
if [ $? -eq 0 ]; then
  logger "INFO" "Migration master database. Successfully" $LOG
fi

