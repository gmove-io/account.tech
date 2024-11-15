import { Transaction } from "@mysten/sui/transactions";
import { OwnedObjectRef } from "@mysten/sui/client";
import * as fs from "fs";
import * as TOML from "@iarna/toml";
import * as path from "path";
import { client, keypair, IObjectInfo, getId } from "./utils.js";

/// Package name must be in PascalCase and named address must be in snake_case in Move.toml
/// Example: packageName = "AccountExtensions" -> packageNamedAddress = "account_extensions"
///
/// When using --test, the package will be published on testnet
/// named addresses must be different in [dev-addresses] and [addresses]
/// use "_" as a placeholder in [addresses] if necessary

(async () => {
	// read args from command line
	const args = process.argv.slice(2);
	const packageName = args[0];
	const isDev = args.includes("--dev");
	
	const addressesSection = isDev ? "dev-addresses" : "addresses";
	
	if (!packageName) {
		console.error("Error: Name parameter is required.");
		process.exit(1);
	}
	const isPascalCase = (str: string) => /^[A-Z][a-zA-Z0-9]*$/.test(str);
	if (!isPascalCase(packageName)) {
		console.error("Error: Package name must be in PascalCase and named address must be in snake_case.");
		process.exit(1);
	}
	const packageNamedAddress = packageName.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
	console.log(`Package named address: ${packageNamedAddress}`);

	// find the package path
	const findPackagePath = (dir: string): string | null => {
		const items = fs.readdirSync(dir, { withFileTypes: true });
		for (const item of items) {
			const fullPath = path.join(dir, item.name);
			if (item.isDirectory()) {
				const result = findPackagePath(fullPath);
				if (result) return result;
			} else if (item.name === 'Move.toml') {
				const moveTomlContent = fs.readFileSync(fullPath, 'utf8');
				const parsedToml = TOML.parse(moveTomlContent);
				if (typeof parsedToml.package === 'object' && 'name' in parsedToml.package && parsedToml.package.name === packageName) {
					return dir;
				}
			}
		}
		return null;
	};

	const packagePath = findPackagePath(process.env.PACKAGES_PATH!) || '';

	if (!packagePath) {
		console.error(`Error: Package ${packageName} not found in any Move.toml file.`);
		process.exit(1);
	}
	console.log(`Package path: ${packagePath}`);

	const readline = require("readline").createInterface({
		input: process.stdin,
		output: process.stdout
	});

	// ask for confirmation
	console.log("\x1b[33m\nWARNING: Publishing a new package will delete Move.lock and previously published data will be lost.\x1b[0m");
	await new Promise((resolve) => {
		readline.question("Are you sure you want to continue? (y/n): ", (answer: string) => {
			if (answer.toLowerCase() !== "y") {
				console.log("Operation cancelled.");
				process.exit(0);
			}
			readline.close();
			resolve(void 0);
		});
	});
	
	// Delete Move.lock file before building the package
	const moveLockPath = packagePath + `/Move.lock`;
	if (fs.existsSync(moveLockPath)) {
		try {
			fs.unlinkSync(moveLockPath);
			console.log("Move.lock file deleted successfully.");
		} catch (error) {
			console.error("Error deleting Move.lock file:", error);
		}
	} else {
		console.log("Move.lock file does not exist. Proceeding with the build.");
	}
	
	// Update the Move.toml file to set packageNamedAddress to 0x0 in [dev-addresses]
	const moveTomlPath = packagePath + `/Move.toml`;
	try {
		const moveTomlContent = fs.readFileSync(moveTomlPath, "utf8");
		const parsedToml = TOML.parse(moveTomlContent);
		
		if (parsedToml[addressesSection] && typeof parsedToml[addressesSection] === "object") {
			(parsedToml[addressesSection] as Record<string, string>)[packageNamedAddress] = "0x0";
		}
		
		if (parsedToml.dependencies && typeof parsedToml.dependencies === "object") {
			for (const [key, value] of Object.entries(parsedToml.dependencies)) {
				if (typeof value === "object" && "local" in value) {
					(parsedToml.dependencies as Record<string, { local: string }>)[key] = { local: (value as { local: string }).local };
				}
			}
		}
		
		const updatedToml = TOML.stringify(parsedToml);
		fs.writeFileSync(moveTomlPath, updatedToml);
		console.log(`Updated ${packageNamedAddress} to 0x0 and standardized dependencies format`);
	} catch (error) {
		console.error("Error updating Move.toml:", error);
	}

	console.log("\nbuilding package...")
	
	const { execSync } = require("child_process");
	const { modules, dependencies } = JSON.parse(
		execSync(
			`${process.env.CLI_PATH!} move build --dump-bytecode-as-base64 --path ${packagePath} ${isDev && "--dev"}`, 
			{ encoding: "utf-8" }
		)
	);

	console.log("\npublishing...")

	const tx = new Transaction();
	tx.setGasBudget(1000000000);

	const [upgradeCap] = tx.publish({ modules, dependencies });
	tx.transferObjects([upgradeCap], keypair.getPublicKey().toSuiAddress());
	
	const result = await client.signAndExecuteTransaction({
		signer: keypair,
		transaction: tx,
		options: {
			showEffects: true,
		},
		requestType: "WaitForLocalExecution"
	});

	// return if the tx hasn"t succeed
	if (result.effects?.status?.status !== "success") {
		console.log("\n\nPublishing failed:", result.effects?.status?.error);
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
			console.log("\n\n\x1b[32mSuccessfully deployed at: " + item.data?.objectId + "\x1b[0m");
			objects.push({
				type: packageName,
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
	const dataFolder = isDev ? "testnet-data" : "mainnet-data";
	const filePath = `./src/${dataFolder}/${packageNamedAddress.replace("_", "-")}.json`;
	fs.writeFileSync(filePath, JSON.stringify(objects, null, 2));
	
	execSync(
		`${process.env.CLI_PATH!} move manage-package --environment "$(sui client active-env)" \
			--network-id "$(sui client chain-identifier)" \
			--original-id ${getId(packageName, isDev)} \
			--latest-id ${getId(packageName, isDev)} \
			--version-number "1" \
			--path ${packagePath}`,
		{ encoding: "utf-8" }
	);
	console.log("\nUpdated Move.lock with new package id");

	// Update Move.toml files with the new package address
	const directories = fs.readdirSync(process.env.PACKAGES_PATH!, { withFileTypes: true })
		.filter(dirent => dirent.isDirectory())
		.map(dirent => dirent.name);

	directories.forEach(dir => {
		const moveTomlPath = `${process.env.PACKAGES_PATH!}${dir}/Move.toml`;
		if (fs.existsSync(moveTomlPath)) {
			let content = fs.readFileSync(moveTomlPath, "utf8");
			
			try {
				const parsed = TOML.parse(content);
				
				if (parsed[addressesSection] && typeof parsed[addressesSection] === "object" && packageNamedAddress in parsed[addressesSection]) {
					(parsed[addressesSection] as Record<string, string>)[packageNamedAddress] = getId(packageName, isDev);
					
					const updatedContent = TOML.stringify(parsed);
					fs.writeFileSync(moveTomlPath, updatedContent);
					console.log(`Updated ${moveTomlPath} with new package address`);
				}
			} catch (error) {
				console.error(`Error parsing ${moveTomlPath}: ${error}`);
			}
		}
	});
	
})()