import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';
import { getFullnodeUrl, SuiClient } from '@mysten/sui.js/client';

(async () => {
	try {
		console.log("calling...")

		const client = new SuiClient({ url: getFullnodeUrl("testnet") });

		const { data } = await client.getObject({
			id: "0xf1417c19b66eb13912e85f94a4b6e20a0f121298b2058e023dae8e1b26605120",
			options: {
				showContent: true
			}
		});

		console.log("result: ", JSON.stringify(data, null, 2));

	} catch (e) {
		console.log(e)
	}
})()