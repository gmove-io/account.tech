import { Transaction } from '@mysten/sui/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
    try {
        console.log("calling...")

        const tx = new Transaction();
        tx.setGasBudget(10000000);

        const pkg = getId("AccountExtensions")

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("AccountProtocol"),
                tx.pure.address(getId("AccountProtocol")),
                tx.pure.u64(1),
            ],
        });

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("AccountMultisig"),
                tx.pure.address(getId("AccountMultisig")),
                tx.pure.u64(1),
            ],
        });

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("AccountActions"),
                tx.pure.address(getId("AccountActions")),
                tx.pure.u64(1),
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