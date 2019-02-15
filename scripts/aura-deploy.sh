#!/bin/bash
read -p "Enter new username: " username
sudo adduser $username
if [ $? -ne 0 ]
then
  exit 1
fi

sudo usermod -aG sudo $username
if [ $? -ne 0 ]
then
  exit 1
fi

su $username << EOF
  sudo apt update
  sudo apt-get install apt-transport-https ca-certificates curl software-properties-common -y
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  sudo apt update
  sudo apt install docker-ce -y
EOF

sudo usermod -aG docker $username

su $username << EOF
  sudo apt install docker-compose -y
  sudo apt install build-essential python -y
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash
  sudo apt install npm -y
EOF

su $username << EOF
  cd "/home/$username/"
  source ".nvm/nvm.sh"
  nvm install 10.15
  npm install -g @auroradao/aurad-cli
EOF
