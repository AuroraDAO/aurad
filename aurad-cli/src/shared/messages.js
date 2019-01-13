const version = require('../../package.json').version;
const chalk = require('chalk');

const padding = (str, f) => {
  let i = process.stdout.columns - str.length
  let before = '', after = '';
  while (i--) {
    i % 2 == 0 ? before += ' ' : after += ' ';
  }
  f = f || chalk.white.bgBlack;
  return [f(before), f(after)];
}

module.exports = {
  WELCOME_MESSAGE: `AuraD v${version}`,
  WALLET_EXPLAINER: `
    For AuraD staking, you need a wallet with a minimum of 10,000 AURA held for 7 days.
    We recommend using a cold wallet for security purposes.
    
    Once we verify ownership of your cold wallet, AuraD will generate a local hot wallet for you.
  `,
  WALLET_PROMPT: 'Cold wallet address',

  TESTMAIL_SUBJECT: 'AuraD Testmail',
  TESTMAIL_CONTENT: 'This Email was generated and sent by the AuraD node. If you can read this your Email-Configuration is working correctly.'

}
