# RSFlashLoanAdapter

RSFlashloanAdapter enables Rhinestone relayers to atomically fill intents using Aave V3 flashloans without pre-funding liquidity.

It provides a simple `flashFill` function callable only by the relayer - in this case, we assume that the relayer is deployer/owner for this contract. (This might not be necessary and it might be possible to use this as a generic shared tool across multiple relayers.)

`flashFill` requests a flashloan and executes an encoded SpokePool.fill call within Aave's executeOperation callback. The adapter is designed to be generic, supporting both overloads of fill, and forwards arbitrary calldata to the SpokePool to be a bit future-proof here.

Access control and Aave callback validations are enforced.

Missing functionality: `_handleFlashloanLogic` currently assumes the relayer prepares full calldata for fill externally; no decoding or dynamic construction of fill parameters is done on-chain. Further optimizations like dynamic fee calculation or gas refund handling could be layered later if needed. Additional fine-tuning might be needed to fit the needs of the off-chain solver node as well.
