# Frequently Asked Questions
If you have problems with the installation or maintenance of your node, please take a look at the frequently asked questions. You can also contact the IDEX support staff on the [IDEX Discord server](https://discord.gg/tQa9CAB).

## Node Installation

### Can I use a different VPS provider to Digital Ocean?
Yes you can, however if you are not well versed in operating an Ubuntu operating system using the command line or with VPS in general it is suggested to use Digital Ocean to be able to follow the guides.

### How can I connect to my VPS?
[PuTTY](https://www.putty.org/) is a lightweight and free SSH client which you can use to connect to your VPS from a Windows machine.

### I am having trouble creating SSH keys
Have a look at this [guide](https://www.digitalocean.com/community/tutorials/how-to-create-ssh-keys-with-putty-to-connect-to-a-vps).

### "Command 'nvm' not found, did you mean: ..."
Make sure you installed `nvm` by running
`curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash`
Then **logout** and **login** again.

### "\<user\> is not in the sudoers file."
Add your user to the sudoers file and try again: `usermod -aG sudo <user>`. If you do not have a non-root user you can create a new one with `adduser newuser` first.

### "Couldn't connect to Docker daemon:"
Run `sudo usermod -aG docker ${USER}`, **do not** replace anything in that command, run it as-is. Then **logout** and **login** again.

### "Command failed: docker-compose -f  ..."
Run `sudo usermod -aG docker ${USER}`, **do not** replace anything in that command, run it as-is. Then **logout** and **login** again.

	
## Node maintenance

### "ERROR: Your cold wallet is not qualified for staking"
You either do not meet the required staking amount (10,000 AURA for Tier 3 staking) or your incubation period (currently 7 days) is not over yet.

### "RPC connect timeout"
There can be some problems with the Parity RPC client. A workaround is to use [Infura](https://infura.io/). Register an account and create an API-Key. Then start your node with 
`aura start --rpc https://mainnet.infura.io/v3/<YOUR API KEY>`.

### "STAKING OFFLINE: Your staker is out of sync with the blockchain"
Syncing is still in progress. When your node reaches the latest block it will start staking. [Etherscan](https://etherscan.io/) is one of many block explorers which display the currently latest block.

### "STAKING OFFLINE: Your health check failed or timed out."
If this appears on multiple successive lines check that your node is reachable on port 8443/TCP. [Here](https://www.yougetsignal.com/tools/open-ports/) is an example tool.

### "STAKING OFFLINE: Internal server error / undefined"
This is a known problem and the devs are actively working on a fix. 

