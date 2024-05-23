import { TransactionBlock } from '@mysten/sui.js/transactions';
import { OwnedObjectRef } from '@mysten/sui.js/client';
import * as fs from "fs";
import { client, keypair, IObjectInfo, getId } from './utils.js';

(async () => {
	console.log("building package...")
	
	const { execSync } = require('child_process');
	const { modules, dependencies } = JSON.parse(
	execSync(`${process.env.CLI_PATH!} move build --dump-bytecode-as-base64 --path ${process.env.PACKAGE_PATH!}`, {
		encoding: 'utf-8',
	}),
	);

	console.log("publishing...")

	try {		
		const tx = new TransactionBlock();
		const [upgradeCap] = tx.publish({ modules,dependencies });
		tx.transferObjects([upgradeCap], keypair.getPublicKey().toSuiAddress());
		
		const result = await client.signAndExecuteTransactionBlock({
			signer: keypair,
			transactionBlock: tx,
			options: {
				showEffects: true,
			},
			requestType: "WaitForLocalExecution"
		});
		
		console.log("result: ", JSON.stringify(result, null, 2));

		// return if the tx hasn't succeed
		if (result.effects?.status?.status !== "success") {
			console.log("\n\nPublishing failed");
            return;
        }

		// get all created objects IDs
		const createdObjectIds = result.effects.created!.map(
            (item: OwnedObjectRef) => item.reference.objectId
        );

		// fetch objects data
		const createdObjects = await client.multiGetObjects({
            ids: createdObjectIds,
            options: { showContent: true, showType: true, showOwner: true }
        });

        const objects: IObjectInfo[] = [];
        createdObjects.forEach((item) => {
            if (item.data?.type === "package") {
				objects.push({
					type: "package_id",
					id: item.data?.objectId,
				});
            } else if (!item.data!.type!.startsWith("0x2::")) {
				objects.push({
					type: item.data?.type!.slice(68),
					id: item.data?.objectId,
				});
            } else {
				objects.push({
					type: item.data?.type!.slice(5),
					id: item.data?.objectId,
				});
            }
        });

		fs.writeFileSync('./created.json', JSON.stringify(objects, null, 2));
		
	} catch (e) {
		console.log(e);
	} finally {
        console.log("\n\nSuccessfully deployed at: " + getId("package"));
	}
})()