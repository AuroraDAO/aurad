const {Command, flags} = require('@oclif/command')
const Listr = require('listr');
const chalk = require('chalk');
const rxjs = require('rxjs');
const moment = require('moment');
const fs = require('fs');
const {cli} = require('cli-ux');
const crypto = require('crypto');
const request = require('request-promise');
const request_errors = require('request-promise/errors');
const Docker = require('../shared/docker');
const Parity = require('../shared/parity');
const messages = require('../shared/messages');
const BigNumber = require('bignumber.js');
const homedir = require('os').homedir();
const nodemailer = require("nodemailer");

const STAKING_HOST = 'https://sc.idex.market';
const parity = new Parity('http://offline');

const docker = new Docker();
docker.ensureDirs();

async function getChallenge(address) {
  return new Promise((resolve, reject) => {
    request({
      uri: `${STAKING_HOST}/wallet/${address}/challenge`,
      json: true,
    }).then(result => {
      resolve(result.message);
    }).catch(request_errors.StatusCodeError, reason => {
      reject(reason.statusCode);
    });
  });
}

async function getBalance(address) {
  return request({
    uri: `${STAKING_HOST}/wallet/${address}/balance`,
    json: true,
  });
}

async function submitChallenge(coldWallet, hotWallet, signature) {
  return new Promise((resolve, reject) => {
    request({
      method: 'POST',
      uri: `${STAKING_HOST}/wallet/${coldWallet}/challenge`,
      json: {
        hotWallet,
        signature
      },
    })
    .then(resolve)
    .catch(request_errors.StatusCodeError, reason => {
      reject(reason.statusCode);
    });
  });
}

async function anykey(cli, message) {
  const char = await cli.prompt(message, {type: 'single', required: false})
  process.stderr.write('\n')
  return char
}

async function sendTestMail(service, address, password) {
  const transport = nodemailer.createTransport({
      service: service,
      auth: {
          user: address,
          pass: password
      }
  });

  const mailOptions = {
    from: "AuraD <" + address + ">",
    to: address,
    subject: messages.TESTMAIL_SUBJECT,
    html: messages.TESTMAIL_CONTENT
  }

  return transport.sendMail(mailOptions);
}

class ConfigCommand extends Command {
  async run() {
    console.log('\n')
    let setupMail = await cli.prompt('    ' + chalk.blue.bgWhite("Do you want to setup Email notifications? (Y/N)"));   

    let hasMail;
    let mailService = ""
    let mailAddress = ""
    let mailPassword = ""

    if(setupMail == "Y" || setupMail == "y") {

      let enterNewMailConfiguration = true;
      while(enterNewMailConfiguration) {

        hasMail = false;

        console.log('\n');
        mailService = await cli.prompt('    ' + chalk.blue.bgWhite("Email-Service (see www.nodemailer.com/smtp/well-known/ for a list of available services)")); 
        mailAddress = await cli.prompt('    ' + chalk.blue.bgWhite("Email-Address")); 
        mailPassword = await cli.prompt('    ' + chalk.blue.bgWhite("Email-Password"), {type: 'mask'});
        console.log('\n');

        console.log('    Trying to send a test mail to ' + mailAddress);

        let error = false;
        try {
          await sendTestMail(mailService, mailAddress, mailPassword);
          console.log(`    ${chalk.green('SUCCESS')}: Mail was sent successfully. Please check your inbox and spam folder to check if everything is working correctly.`);
          hasMail = true;
        } catch(err) {
          console.log(`    ${chalk.red('ERROR')}: Could not send mail: ${err}`);
          error = true;
        }

        console.log('\n');

        let keepMailConfig;
        if(error) {
          keepMailConfig = await cli.prompt('    ' + chalk.blue.bgWhite("Do you want to continue without an Email configuration? (Y/N)")); 
        } else {
           keepMailConfig = await cli.prompt('    ' + chalk.blue.bgWhite("Do you want to keep this Email configuration? (Y/N)"));   
        }

        if(keepMailConfig == "Y" || keepMailConfig == "y") {
            enterNewMailConfiguration = false;
        }
        
      }
    }
    
    const {flags} = this.parse(ConfigCommand);
    console.log(messages.WALLET_EXPLAINER);
 
    const containers = await docker.getRunningContainerIds();
    if (containers['aurad']) {
      console.log(`Error: aurad is running, please run 'aura stop' before updating your config`);
      return;
    }
   
    let coldWallet = await cli.prompt('    ' + chalk.blue.bgWhite(messages.WALLET_PROMPT));      
    let challenge;
    try {
      challenge = await getChallenge(coldWallet);
    } catch(status) {
      if (status == 403) {
        console.log(`    ${chalk.red('ERROR')}: Your cold wallet is not qualified for staking`);
      } else {
        console.log(`    ${chalk.red('ERROR')}: Unknown error getting signing challenge`);
      }
      return;   
    }
    
    const { balance } = await getBalance(coldWallet);
    
    console.log('');
    
    let balanceFormatted = (new BigNumber(balance)).dividedBy(new BigNumber('1000000000000000000')).toString();
    
    console.log(`\n    Your staked ${chalk.cyan('AURA')} balance is ${balanceFormatted}.`);
    console.log(`    Use https://www.myetherwallet.com/signmsg.html or your preferred wallet software to sign this *exact* message:\n    ${chalk.blue.bgWhite(challenge)}${chalk.white.bgBlack('  ')}\n`);

    let signature = await cli.prompt('    "sig" value', {type: 'mask'});
    
    let recovered;
    try {
      recovered = await parity.web3.eth.accounts.recover(challenge, signature);
    } catch(e) {
      console.log('Error decoding sig value');
      return;
    }
    
    if (recovered.toLowerCase() != coldWallet.toLowerCase()) {
      console.log(`    ${chalk.red('ERROR')}: Your cold wallet is ${coldWallet.toLowerCase()} but you signed with ${recovered.toLowerCase()}`);
      return;
    }
    
    console.log('    Wallet signature confirmed.');
    
    let newAccount = await parity.web3.eth.accounts.create();
    

    



    try {   
      let result = await submitChallenge(coldWallet, newAccount.address, signature);  

      const buffer = await crypto.randomBytes(16);
      const token = buffer.toString('hex');
      
      let keystore = parity.web3.eth.accounts.encrypt(newAccount.privateKey, token);
  
      const settings = {
        coldWallet,
        token,
        hotWallet: keystore,
        hasMail,
        mailService,
        mailAddress,
        mailPassword
      };
  
      fs.writeFileSync(`${homedir}/.aurad/ipc/settings.json`, JSON.stringify(settings));        
      console.log('\n    Staking wallet confirmed. Run \'aura start\' to download IDEX trade history and begin staking.\n');
    } catch(e) {
      console.log('\n    Error submitting cold wallet challenge');
    }
  }
}

ConfigCommand.description = `Configure your staking wallet`

ConfigCommand.flags = {
}

module.exports = ConfigCommand
