#!/bin/bash
#########################################
# create aura systemd service scripts.
#########################################

read -p "Enter aura service account: " username
getent passwd $username > /dev/null 2>&1
if [ $? -ne 0 ]
then
  echo "Invalid username"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#########################################
# 1. create aura systemd service
#########################################
cat > aura.service << EOF
[Unit]
Description=aurad monitoring service

[Service]
User=$username
WorkingDirectory=/home/$username/
ExecStart=${DIR}/aura-start.sh
ExecStop=${DIR}/aura-stop.sh
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

sudo mv aura.service /etc/systemd/system/

#########################################
# 2. create systemd start up script.
#########################################
aura_start_option=""
read -p "Using https://infura.io? (y/n): " infuraoption
if [ "$infuraoption" == "y" ]; then
  read -p "Enter infura.io endpoint: " infuraurl
  aura_start_option="--rpc $infuraurl"
  monitor_services="docker_aurad_1\|docker_mysql_1"
  monitor_services_count=2
  cat > aura.conf << EOF
rpc_option=1
rpc_url="$infuraurl"
EOF
else
  monitor_services="docker_aurad_1\|docker_parity_1\|docker_mysql_1"
  monitor_services_count=3
fi

cat > aura-start.sh << EOF
#!/bin/bash
source /home/$username/.nvm/nvm.sh
DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"

printConfiguration()
{
  echo "interval=\$interval"
  echo "off_restart=\$off_restart"
  echo "off_cool=\$off_cool"
  echo "sendmail=\$sendmail"
  echo "mail_subject=\$mail_subject"
  echo "mail_message=\$mail_message"
  echo "mail_to=\$mail_to"
  echo "update_notify=\$update_notify"
  echo "update_auto=\$update_auto"
  echo "update_check_interval=\$update_check_interval"
  echo "rpc_option=\$rpc_option"
  echo "rpc_url=\$rpc_url"
  echo "stats_option=\$stats_option"
}

if [ -f "\${DIR}/aura.conf" ]; then
  source "\${DIR}/aura.conf"
  echo "Loading aura.conf settings."
  printConfiguration
fi

initConfiguration()
{
  #check interval minutes (value range 1-59)
  [ -z "\$interval" ] && interval=1
  #staking offline count before restart aurad
  [ -z "\$off_restart" ] && off_restart=3
  #staking offline cooling period after restart aurad
  [ -z "\$off_cool" ] && off_cool=10
  #send mail on staking offline option
  [ -z "\$sendmail" ] && sendmail=0
  #send mail on staking offline mail options
  [ -z "\$mail_subject" ] && mail_subject="AURA STAKING OFFLINE."
  [ -z "\$mail_message" ] && mail_message="AURA STAKING OFFLINE."
  [ -z "\$mail_to" ] && mail_to="your@email.com"
  #aurad update notification option
  [ -z "\$update_notify" ] && update_notify=0
  #aurad auto upgrade  option
  [ -z "\$update_auto" ] && update_auto=0
  #aurad update check interval (value range 1-59)
  [ -z "\$update_check_interval" ] && update_check_interval=20
  #external ethereum node option
  [ -z "\$rpc_option" ] && rpc_option=0
  [ -z "\$rpc_url" ] && rpc_url=""
  #statistics logging option
  [ -z "\$stats_option" ] && stats_option=0
}

initVariables()
{
  sysminutes=\$((\$(date +"%-M")))
  off_count=0
  off_count_cool=0
  lastminutes=-1
  latest_pkg_version=""
  logs_aurad=""
  if [ \$rpc_option -eq 1 ] && [ ! -z "\$rpc_url" ]; then
    services_count=2
    services_names="docker_aurad_1\|docker_mysql_1"
  else
    services_count=3
    services_names="docker_aurad_1\|docker_parity_1\|docker_mysql_1"
  fi
}

fetchAuradLogs()
{
  logs_aurad=\$(aura logs -n aurad | tail -n 20)
}

fetchAuradStatus()
{
  logs_aurad=\$(aura status)
  if [ -z "\$logs_aurad" ]; then
    stat_status=""
    stat_reason=""
    my_period_credit=""
    tot_period_credit=""
    staked=""
    tot_staked=""
    echo "Unable to get aura status..."
    return 1
  fi
  stat_status=""
  stat_reason=""
  test=\$(grep "Staking: offline" -c <<< "\$logs_aurad")
  if [ \$test -eq 1 ]; then
    stat_status=0
    stat_reason="offline"
  fi
  if [[ \$(grep "Staking: online" -c <<< "\$logs_aurad") -eq 1 ]]; then
    stat_status=1
  fi
  my_period_credit=\$(grep "My Period Credits"  <<< "\$logs_aurad" | awk -F ' ' '{print \$6}')
  tot_period_credit=\$(grep "My Period Credits"  <<< "\$logs_aurad" | awk -F ' ' '{print \$8}')
  staked=\$(grep "^Staked AURA"  <<< "\$logs_aurad" | awk -F ' ' '{print \$3}')
  tot_staked=\$(grep "^Total Staked AURA"  <<< "\$logs_aurad" | awk -F ' ' '{print \$4}')
  return 0
}

checkAuradSnapshot()
{
  snapshot=\$(grep 'snapshot' <<< "\$logs_aurad" | tail -n 1)
}

checkAuradProcessingBlock()
{
  processingblock=\$(grep 'Processing blocks' <<< "\$logs_aurad" | tail -n 1 | cut -d '|' -f3 | cut -d ' ' -f6)
}

waitAuradSnapshotSync()
{
  while :
  do
    checkAuradSnapshot
    if [ -z "$snapshot" ]; then
      break
    else
      echo  "still active"
    fi
    sleep 10
    fetchAuradLogs
  done
}

parseEthBlockNumber()
{
  blocknum=\$((16#\$(echo \${1:1:-1} | cut -d '"' -f10 | sed 's/0x//g')))
}

checkEthBlockNumber()
{
  jresult=\$(curl -s "https://api.etherscan.io/api?module=proxy&action=eth_blockNumber&apikey=YourApiKeyToken")
  if [ \$? -ne 0 ]; then
    return 1
  fi
  parseEthBlockNumber \$jresult
  if [ \$? -ne 0 ]; then
    return 2
  fi
  return 0
}

waitAuradBlockSync()
{
  lastblocknum=0
  stuck_count=0
  while :
  do
    checkEthBlockNumber
    fetchAuradLogs
    if [ \$? -eq 0 ]; then
      checkAuradProcessingBlock
      if [ ! -z "\$processingblock" ]; then
        echo "Waiting block sync (\$processingblock/\$blocknum)"
        if [[ \$((blocknum - processingblock)) -lt 6 ]]; then
          break
        fi
      fi
    fi
    if [ ! -z "\$processingblock" ] && [ ! -z "\$lastblocknum" ]  && [ \$lastblocknum -eq \$processingblock ]; then
      stuck_count=\$((stuck_count+1))
      if [ \$stuck_count -ge 3 ]; then
        echo "Aurad container block sync stuck. Restarting aurad cointainer."
        docker restart docker_aurad_1
        stuck_count=0
      fi
    else
      stuck_count=0
    fi
    lastblocknum=\$processingblock
    sleep 50
  done
  #Extra wait time for aurad container to active running
  sleep 30
}

checkAuradPackageVersion()
{
  if  [ -z "\$current_pkg_version" ]; then
    current_pkg_version=\$(npm ls -g  @auroradao/aurad-cli | grep "@auroradao.aurad-cli" | cut -d '@' -f3 | tr -d '[:space:]')
  fi
  latest_pkg_version=\$(npm dist-tag ls @auroradao/aurad-cli | cut -d ' ' -f2)
  if [ ! -z "\$latest_pkg_version" ] && [ ! -z "\$current_pkg_version" ] && [ "\$current_pkg_version" != "\$latest_pkg_version" ]; then
    echo "New aurad package available (\$latest_pkg_version)."
    if [ \$update_notify -eq 1 ]; then
      echo "Software update version: \$latest_pkg_version" | mail -s "Software update" "\$mail_to"
    fi
    if [ \$update_auto -eq 1 ]; then
      updateAura
    fi
    current_pkg_version=\$(npm ls -g  @auroradao/aurad-cli | grep "@auroradao.aurad-cli" | cut -d '@' -f3 | tr -d '[:space:]')
  fi
}

formatJson()
{
  echo "\"\$1\":\"\$2\""
}

logStatistics()
{
  stat_interval=\$interval
  stat_time=\$(date +%Y%m%d%H%M%S)
  ppid=\$(pidof parity)
  if [ ! -z "\$ppid" ]; then
    psout=\$(ps -p \$ppid -o %cpu,vsz,rss --no-headers)
  else
    psout=""
  fi
  if [ ! -z "\$psout" ]; then
    stat_parity_cpu=\$(awk -F' ' '{printf "%.2f", \$1}' <<< "\$psout")
    stat_parity_vmem=\$(awk -F' ' '{printf "%.2f", \$2/1024}' <<< "\$psout")
    stat_parity_mem=\$(awk -F' ' '{printf "%.2f", \$3/1024}' <<< "\$psout")
  else
    stat_parity_cpu=""
    stat_parity_vmem=""
    stat_parity_mem=""
  fi
  psout=\$(ps -p \$(pidof node aurad) -o %cpu,vsz,rss --no-headers)
  if [ ! -z "\$psout" ]; then
    stat_aurad_cpu=\$(awk -F' ' '{printf "%.2f", \$1}' <<< "\$psout")
    stat_aurad_vmem=\$(awk -F' ' '{printf "%.2f", \$2/1024}' <<< "\$psout")
    stat_aurad_mem=\$(awk -F' ' '{printf "%.2f", \$3/1024}' <<< "\$psout")
  else
    stat_aurad_cpu=""
    stat_aurad_vmem=""
    stat_aurad_mem=""
  fi
  psout=\$(ps -p \$(pidof mysqld) -o %cpu,vsz,rss --no-headers)
  if [ ! -z "\$psout" ]; then
    stat_mysqld_cpu=\$(awk -F' ' '{printf "%.2f", \$1}' <<< "\$psout")
    stat_mysqld_vmem=\$(awk -F' ' '{printf "%.2f", \$2/1024}' <<< "\$psout")
    stat_mysqld_mem=\$(awk -F' ' '{printf "%.2f", \$3/1024}' <<< "\$psout")
  else
    stat_mysqld_cpu=""
    stat_mysqld_vmem=""
    stat_mysqld_mem=""
  fi
  psout=\$(ps -p \$$ -o %cpu,vsz,rss --no-headers)
  if [ ! -z "\$psout" ]; then
    stat_aura_cpu=\$(awk -F' ' '{printf "%.2f", \$1}' <<< "\$psout")
    stat_aura_vmem=\$(awk -F' ' '{printf "%.2f", \$2/1024}' <<< "\$psout")
    stat_aura_mem=\$(awk -F' ' '{printf "%.2f", \$3/1024}' <<< "\$psout")
  else
    stat_aura_cpu=""
    stat_aura_vmem=""
    stat_aura_mem=""
  fi
  
  logline="{\$(formatJson "t" \$stat_time)"
  logline="\$logline,\$(formatJson "i" \$stat_interval)"
  logline="\$logline,\$(formatJson "s" \$stat_status)"
  logline="\$logline,\$(formatJson "pc" \$stat_parity_cpu)"
  logline="\$logline,\$(formatJson "pm" \$stat_parity_mem)"
  logline="\$logline,\$(formatJson "pv" \$stat_parity_vmem)"
  logline="\$logline,\$(formatJson "ac" \$stat_aurad_cpu)"
  logline="\$logline,\$(formatJson "am" \$stat_aurad_mem)"
  logline="\$logline,\$(formatJson "av" \$stat_aurad_vmem)"
  logline="\$logline,\$(formatJson "mc" \$stat_mysqld_cpu)"
  logline="\$logline,\$(formatJson "mm" \$stat_mysqld_mem)"
  logline="\$logline,\$(formatJson "mv" \$stat_mysqld_vmem)"
  logline="\$logline,\$(formatJson "dc" \$stat_aura_cpu)"
  logline="\$logline,\$(formatJson "dm" \$stat_aura_mem)"
  logline="\$logline,\$(formatJson "dv" \$stat_aura_vmem)"
  logline="\$logline,\$(formatJson "cc" \$my_period_credit)"
  logline="\$logline,\$(formatJson "ct" \$tot_period_credit)"
  logline="\$logline,\$(formatJson "ss" \$staked)"
  logline="\$logline,\$(formatJson "st" \$tot_staked)"
  logline="\$logline,\$(formatJson "r" \$stat_reason)"
  logline="\$logline}"

  if [ ! -d "\${DIR}/stats" ]; then
    mkdir "\${DIR}/stats"
  fi
  cat >> "\${DIR}/stats/\${stat_time:0:8}.txt" <<< "\$logline"
}

startAura()
{
  if [ \$rpc_option -eq 1 ] && [ ! -z "\$rpc_url" ]; then
    aura start --rpc "\$rpc_url"
  else
    aura start
  fi
}

stopAura()
{
  aura stop
}

restartAura()
{
  stopAura
  startAura
}

updateAura()
{
  stopAura
  npm install -g @auroradao/aurad-cli
  startAura
}

#############################################################
## Main routine area
#############################################################
initConfiguration
initVariables
checkAuradPackageVersion
startAura
waitAuradSnapshotSync
##wait sync block differences less than 6 blocks
waitAuradBlockSync

echo "Monitoring started..."
while :
do
  sysminutes=\$((\$(date +"%-M")))

  if [ \$((\$sysminutes % \$update_check_interval)) -eq 0 ]; then
    checkAuradPackageVersion
  fi

  if [[ \$(docker ps --format "{{.Names}}"  --filter status=running | grep -c "\$services_names") -lt \$services_count ]]; then
    echo "container not running.."
    stat_reason="container not running.."
    stat_status=0
    exit 1
  else
    if [ \$((\$sysminutes % \$interval)) -eq 0 ] && [ \$lastminutes -ne \$sysminutes ]; then
      lastminutes=\$sysminutes
      fetchAuradStatus
      if [ \$stat_status -eq 0 ]; then
        if [ \$off_count_cool -eq 0 ]; then
          off_count=\$((off_count+1))
          echo "Staking offline. Fail: \$off_count / \$off_restart."
          if [ \$off_count -eq \$off_restart ]; then
            echo "Restarting aura..."
            off_count=0
            off_count_cool=\$off_cool
            restartAura
          fi
        else
          echo "staking offline."
        fi
        if [ \$sendmail -eq 1 ]; then
          echo "\$mail_message" | mail -s "\$mail_subject" "\$mail_to"
        fi
      else
        if [ \$stat_status -eq 1 ]; then
          if [ \$off_count -ge 1 ]; then
            echo "staking is online..."
          fi
        fi
        off_count=0
      fi

      if [ \$off_count_cool -ge 1 ]; then
        off_count_cool=\$((off_count_cool - 1))
        echo "Restart cooling period \$((off_cool - off_count_cool)) / \$off_cool."
      fi
      if [ \$stats_option -eq 1 ]; then
        logStatistics
      fi
    fi
  fi
  sleep 30;
done
EOF

sudo chmod +x aura-start.sh

#########################################
# 3. create systemd stop script.
#########################################
cat > aura-stop.sh << EOF
#!/bin/bash
source /home/$username/.nvm/nvm.sh
aura stop
EOF

sudo chmod +x aura-stop.sh

#########################################
# 4. enable and reload systemd settings.
#########################################
sudo systemctl daemon-reload
sudo systemctl enable aura.service
