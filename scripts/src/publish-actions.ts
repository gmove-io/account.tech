import { Transaction } from '@mysten/sui/transactions';
import { OwnedObjectRef } from '@mysten/sui/client';
import * as fs from "fs";
import { client, keypair, IObjectInfo, getId } from './utils.js';

(async () => {
	console.log("building package...")
	
	const { execSync } = require('child_process');
	const { modules, dependencies } = JSON.parse(
		execSync(
			`${process.env.CLI_PATH!} move build --dump-bytecode-as-base64 --path ${process.env.ACTIONS_PATH!}`,
			{ encoding: 'utf-8' }
		)
	);

	console.log("publishing...")

	try {		
		const tx = new Transaction();
		tx.setGasBudget(1000000000);

		const [upgradeCap] = tx.publish({ modules,dependencies });
		tx.transferObjects([upgradeCap], keypair.getPublicKey().toSuiAddress());
		
		const result = await client.signAndExecuteTransaction({
			signer: keypair,
			transaction: tx,
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
				console.log("\n\nSuccessfully deployed at: " + item.data?.objectId);
				objects.push({
					type: "actions-package",
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

		fs.writeFileSync('./src/data/actions-created.json', JSON.stringify(objects, null, 2));
		
	} catch (e) {
		console.log(e);
	} finally {
		execSync(
			`${process.env.CLI_PATH!} move manage-package --environment "$(sui client active-env)" \
				--network-id "$(sui client chain-identifier)" \
				--original-id ${getId("actions-package")} \
				--latest-id ${getId("actions-package")} \
				--version-number '1' \
				--path ${process.env.ACTIONS_PATH!}`,
			{ encoding: 'utf-8' }
		)
	};
})()