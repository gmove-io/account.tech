import { Transaction } from '@mysten/sui/transactions';
import { client, keypair, getId } from './utils.js';

export async function initExtensions(): Promise<boolean> {
    console.log("\n🔧 Initializing extensions...");
    try {
        const tx = new Transaction();
        tx.setGasBudget(10000000);

        const pkg = getId("AccountExtensions");

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
                tx.pure.string("AccountActions"),
                tx.pure.address(getId("AccountActions")),
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

        const result = await client.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
            options: {
                showObjectChanges: true,
                showEffects: true,
            },
            requestType: "WaitForLocalExecution"
        });

        if (result.effects?.status?.status === "success") {
            console.log("✅ Core dependencies initialized successfully");
            return true;
        } else {
            console.error("❌ Failed to initialize core dependencies:", result.effects?.status?.error);
            return false;
        }
    } catch (error) {
        console.error("❌ Failed to initialize core dependencies:", error);
        return false;
    }
}