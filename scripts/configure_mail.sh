#!/bin/bash

cat << EOF
*************************************************************************************
If you are using gmail account please make sure security setting
  "Allow less secure app: ON"

Login to gmail acccount and visit following link to check your gmail account setting:
  https://myaccount.google.com/lesssecureapps
*************************************************************************************
EOF

read -p "Enter mail server name (eg. smtp.gmail.com): " smtp_server
read -p "Enter mail server port (eg. 587): " smtp_port
read -p "Enter your email (eg. username@gmail.com): " email
while :
do
  echo -n "Enter your email password: "
  read -s password
  echo
  echo -n "Enter your email password again: "
  read -s password2
  echo
  if [ "$password" == "$password2" ]; then
    break
  else
    echo "Password not match! Please try again."
  fi
done

if [ -z "$smtp_server" ] || [ -z "$smtp_port" ] || [ -z "$email" ] || [ -z "$password" ]; then
  echo "Insufficient input to configure email."
  exit 1
else
  echo "Mail server: [$smtp_server]:$smtp_port"
  echo "Email: $email"
fi

debconf-set-selections <<< "postfix postfix/mailname string $(hostname)"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
sudo apt-get install postfix mailutils -y
sasl_options="[${smtp_server}]:${smtp_port} ${email}:${password}"
cat >> /etc/postfix/sasl/sasl_passwd <<< "$sasl_options" 
sudo postmap /etc/postfix/sasl/sasl_passwd

sudo chown root:root /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
sudo chmod 0600 /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db

sudo postconf -e "relayhost = [${smtp_server}]:${smtp_port}"
sudo postconf -e "smtp_sasl_auth_enable = yes"
sudo postconf -e "smtp_sasl_security_options = noanonymous"
sudo postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd"
sudo postconf -e "smtp_tls_security_level = encrypt"
sudo postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

sudo service postfix restart
mail -s "test mail" "$email" <<< "This is test mail."
