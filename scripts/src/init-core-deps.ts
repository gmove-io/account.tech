import { Transaction } from '@mysten/sui/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
    try {
        console.log("calling...")

        const tx = new Transaction();
        tx.setGasBudget(10000000);

        const pkg = getId("KrakenExtensions")

        tx.moveCall({
            target: `${pkg}::extensions::init_core_deps`,
            arguments: [
                tx.object(getId("extensions::AdminCap")),
                tx.object(getId("extensions::Extensions")),
                tx.pure.vector("address", [getId("KrakenMultisig"), getId("KrakenActions")])
            ],
        });

        const result = await client.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
            options: {
                showObjectChanges: true,
                showEffects: true,
            },
            requestType: "WaitForLocalExecution"
        });

        console.log("result: ", JSON.stringify(result.objectChanges, null, 2));
        console.log("status: ", JSON.stringify(result.effects?.status, null, 2));

    } catch (e) {
        console.log(e)
    }
})()