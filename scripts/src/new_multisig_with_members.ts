import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
	try {
		console.log("calling...")

		const tx = new TransactionBlock();

		const pkg = getId("package_id")

		let members = [
			"0x608f5242acdbe2bc779de586864dc914d0dee1adfe4654b560bd5019886daa29"
		]

		const [multisig] = tx.moveCall({
			target: `${pkg}::multisig::new`,
			arguments: [tx.pure("test")],
		});

		tx.moveCall({
			target: `${pkg}::config::propose_modify`,
			arguments: [
				multisig, 
				tx.pure("init_members"), 
				tx.pure(0), 
				tx.pure(0), 
				tx.pure(""), 
				tx.pure([]), 
				tx.pure([]), 
				tx.pure(members),
				tx.pure([]), 
			],
		});

		tx.moveCall({
			target: `${pkg}::multisig::approve_proposal`,
			arguments: [
				multisig, 
				tx.pure("init_members"), 
			],
		});

		tx.moveCall({
			target: `${pkg}::config::execute_modify`,
			arguments: [
				multisig, 
				tx.pure("init_members"), 
				tx.object("0x6"),
			],
		});

		members.forEach((member) => {
			tx.moveCall({
				target: `${pkg}::account::send_invite`,
				arguments: [multisig, tx.pure(member)],
			});
		})

		tx.moveCall({
			target: `${pkg}::multisig::share`,
			arguments: [multisig],
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