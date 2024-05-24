import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';
import { getFullnodeUrl, SuiClient } from '@mysten/sui.js/client';

(async () => {
	try {
		console.log("calling...")

		const client = new SuiClient({ url: getFullnodeUrl("testnet") });

		const accounts = await client.getOwnedObjects({
			owner: keypair.toSuiAddress(),
			filter: {
				StructType: `${getId("package_id")}::account::Account`
			},
			options: {
				showContent: true
			}
		});

		console.log("result: ", JSON.stringify(accounts, null, 2));

	} catch (e) {
		console.log(e)
	}
})()