#!/bin/bash
#########################################
# create aura systemd service scripts.
#########################################

read -p "Enter aura service account: " username
getent passwd $username > /dev/null 2&>1
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
else
  monitor_services="docker_aurad_1\|docker_parity_1\|docker_mysql_1"
  monitor_services_count=3
fi

cat > aura-start.sh << EOF
#!/bin/bash
source /home/$username/.nvm/nvm.sh

initConfiguration()
{
  #check interval
  interval=1
  #staking offline count before restart aurad
  off_restart=3
  #staking offline cooling period after restart aurad
  off_cool=10
  #send mail on staking offline option
  sendmail=0
  #send mail on staking offline mail options
  mail_subject="AURA STAKING OFFLINE."
  mail_message="AURA STAKING OFFLINE."
  mail_to="Your@email.com"
  #aurad update notification option
  update_notify=0
}

initVariables()
{
  sysminutes=\$((\$(date +"%-M")))
  off_count=0
  off_count_cool=0
  lastminutes=-1
  last_pkg_version=""
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

checkAuradProcessingBlock()
{
  processingblock=\$(aura logs -n aurad | grep 'Processing blocks' | tail -n 1 | cut -d '|' -f3 | cut -d ' ' -f6)
}

waitAuradBlockSync()
{
  lastblocknum=0
  while :
  do
    checkEthBlockNumber
    if [ \$? -eq 0 ]; then
      checkAuradProcessingBlock
      if [ ! -z "\$processingblock" ]; then
        echo "Waiting block sync (\$processingblock/\$blocknum)"
        if [[ \$((blocknum - processingblock)) -lt 6 ]]; then
          break
        fi
      fi
    fi
    if [ \$lastblocknum -eq \$processingblock ]; then
      echo "Restarting aurad cointainer."
      docker restart docker_aurad_1
    fi
    lastblocknum=\$processingblock
    sleep 20
  done
}

checkAuradPackageVersion()
{
  pkg_version=\$(npm dist-tag ls @auroradao/aurad-cli | cut -d ' ' -f2)
  if [ ! -z "\$last_pkg_version" ] && [ "\$last_pkg_version" != "\$pkg_version" ]; then
    echo "New aurad package available (\$pkg_version)."
    if [ $update_notify -eq 1 ]; then
      echo "Software update version: \$pkg_version" | mail -s "Software update" "\$mail_to"
    fi
  fi
  last_pkg_version=\$pkg_version
}

initConfiguration
checkAuradPackageVersion
aura start $aura_start_option
initVariables
##wait sync block differences less than 6 blocks
waitAuradBlockSync

while :
do
  sysminutes=\$((\$(date +"%-M")))
  
  if [ \$((\$sysminutes % 20)) -eq 0 ]; then
    checkAuradPackageVersion
  fi
  
  if [[ \$(docker ps --format "{{.Names}}"  --filter status=running | grep -c "$monitor_services") -lt $monitor_services_count ]]; then
    echo "container not running.."
    exit 1
  else
    if [ \$((\$sysminutes % \$interval)) -eq 0 ] && [ \$lastminutes -ne \$sysminutes ]; then
      lastminutes=\$sysminutes
      test=\$(aura status | grep "Staking: offline" -c)
      if [ \$test -eq 1 ]; then
        if [ \$off_count_cool -eq 0 ]; then
          off_count=\$((off_count+1))
          echo "Staking offline. Fail: \$off_count / \$off_restart."
          if [ \$off_count -eq \$off_restart ]; then
            echo "Restarting aura..."
            off_count=0
            off_count_cool=\$off_cool
            aura stop
            aura start $aura_start_option
          fi
        else
          echo "staking offline."
        fi
        if [ \$sendmail -eq 1 ]; then
          echo "\$mail_message" | mail -s "\$mail_subject" "\$mail_to"
        fi
      else
        if [ \$off_count -ge 1 ] && [[ \$(aura status | grep "Staking: online" -c) -eq 1 ]]; then
          echo "staking is online..."
        fi
        off_count=0
      fi

      if [ \$off_count_cool -ge 1 ]; then
        off_count_cool=\$((off_count_cool - 1)) 
        echo "Restart cooling period \$((off_cool - off_count_cool)) / \$off_cool."
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
