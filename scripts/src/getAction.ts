import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';
import { getFullnodeUrl, SuiClient } from '@mysten/sui.js/client';

(async () => {
	try {
		console.log("calling...")

		const client = new SuiClient({ url: getFullnodeUrl("testnet") });

		const { data: df } = await client.getDynamicFields({
			parentId: "0xffd58aa5abc287cb483d7f12e42a3d6198c8dcec51e06c312a29eb32fe2a7037",
		});

		const { data } = await client.getObject({
			id: df[0].objectId,
			options: {
				showContent: true
			}
		});

		console.log("result: ", JSON.stringify(data, null, 2));

	} catch (e) {
		console.log(e)
	}
})()