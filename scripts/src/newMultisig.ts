import { Transaction } from '@mysten/sui/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
	try {
		console.log("calling...")

		const tx = new Transaction();

		const pkg = getId("package_id")

		const [multisig] = tx.moveCall({
			target: `${pkg}::multisig::new`,
			arguments: [tx.pure.string("test")],
		});

		tx.moveCall({
			target: `${pkg}::multisig::share`,
			arguments: [multisig],
		});

		tx.setGasBudget(10000000);

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