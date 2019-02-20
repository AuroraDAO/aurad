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

source /home/$username/.nvm/nvm.sh
aura start $aura_start_option
sysminutes=\$((\$(date +"%-M")))
interval=1
off_restart=3
off_cool=10
off_count=0
off_count_cool=0
lastminutes=-1
sendmail=0

mail_subject="AURA STAKING OFFLINE."
mail_message="AURA STAKING OFFLINE."
mail_to="Your@email.com"

##wait sync block differences less than 6 blocks
while :
do
  checkEthBlockNumber
  if [ \$? -ne 0 ]; then
    echo "error"
  else
    checkAuradProcessingBlock
    if [ ! -z "\$processingblock" ]; then
      echo "Waiting block sync (\$processingblock/\$blocknum)"
      if [[ \$((blocknum - processingblock)) -lt 6 ]]; then
        break
      fi
    fi
  fi
  sleep 20
done

while :
do
  sysminutes=\$((\$(date +"%-M")))
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
