# WIP

contract for (donkeverse.com)[donkeverse.com]

Install solc on Mac OS X

```shell
brew update
brew upgrade
brew tap ethereum/ethereum
brew install solidity
```

Do this stuff

```
npx prettier '**/*.{json,sol,md}' --write
npx eslint '**/*.js' --fix
npx solhint 'contracts/**/*.sol' --fix
```

To run slither
`docker run -it -v /home/share:/share trailofbits/eth-security-toolbox`
