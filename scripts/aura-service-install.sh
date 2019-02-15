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
cat > aura-start.sh << EOF
#!/bin/bash
source /home/$username/.nvm/nvm.sh
aura start
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

while :
do
  sysminutes=\$((\$(date +"%-M")))
  if [[ \$(docker ps --format "{{.Image}}"  --filter status=running | grep -c "auroradao\|parity\|mysql") -lt 3 ]]; then
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
            aura restart
          fi
        else
          off_count_cool=\$((off_count_cool - 1)) 
          echo "staking offline. Restart cooling period \$((off_cool - off_count_cool)) / \$off_cool."
        fi
        if [ \$sendmail -eq 1 ]; then
          echo \$mail_message | mail -s \$mail_message \$mail_to
        fi
      else
        if [ \$off_count -ge 1 ] && [[ \$(aura status | grep "Staking: online" -c) -eq 1 ]]; then
          echo "staking is online..."
        fi
        off_count=0
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

