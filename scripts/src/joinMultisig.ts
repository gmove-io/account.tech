import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
	try {
		console.log("calling...")

		const tx = new TransactionBlock();

		const pkg = getId("package_id")

		tx.moveCall({
			target: `${pkg}::account::join_multisig`,
			arguments: [
				tx.object("0x8d10bbbf80b6daa32aa338417bec7d77bd60cd205914b619a93b46ce414d540f"), 
				tx.pure("0x8d10bbbf80b6daa32aa338417bec7d77bd60cd205914b619a93b46ce414d540f")
			],
		});

		tx.setGasBudget(10000000);

		const result = await client.signAndExecuteTransactionBlock({
			signer: keypair,
			transactionBlock: tx,
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