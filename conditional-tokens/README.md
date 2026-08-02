# Vendored Gnosis Conditional Tokens

This directory vendors the Solidity 0.5 Gnosis Conditional Tokens source used by EvePredict deployments.

- Upstream repository: `https://github.com/gnosis/conditional-tokens-contracts`
- Imported commit: `eeefca66eb46c800a9aaab88db2064a99026fde5`
- Deployed artifact: `out/ConditionalTokens.sol/ConditionalTokens.json`

Rebuild the local artifact with:

```bash
forge build --root conditional-tokens
```

The main `Deploy.s.sol` script loads the generated artifact instead of importing the Solidity 0.5 contract directly, because the primary EvePredict contracts and scripts compile with Solidity 0.8.
