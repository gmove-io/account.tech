import { Transaction } from "@mysten/sui/transactions";
import { SuiObjectChange } from "@mysten/sui/client";
import * as fs from "fs";
import * as TOML from "@iarna/toml";
import * as path from "path";
import { client, keypair, IObjectInfo, getId } from "./utils.js";
import { execSync } from "child_process";
import { initExtensions } from "./init-extensions.js";

/// Package name must be in PascalCase and named address must be in snake_case in Move.toml
/// Example: name = "AccountExtensions" -> "account_extensions" = "0x0"

interface Package {
	name: string;
	path: string;
	dependencies: string[];
	published?: boolean;
}

export class PackagePublisher {
	private readonly packages: Map<string, Package>;

	constructor() {
		this.packages = new Map();
	}

	private async confirmPublish(): Promise<boolean> {
		const readline = require("readline").createInterface({
			input: process.stdin,
			output: process.stdout
		});

		return new Promise((resolve) => {
			console.log("\x1b[33m\nWARNING: Publishing packages will delete Move.lock files and previously published data will be lost.\x1b[0m");
			readline.question("Are you sure you want to continue? (y/n): ", (answer: string) => {
				readline.close();
				resolve(answer.toLowerCase() === "y");
			});
		});
	}

	private findMoveTomls(dir: string): string[] {
		const results: string[] = [];
		const items = fs.readdirSync(dir, { withFileTypes: true });

		for (const item of items) {
			const fullPath = path.join(dir, item.name);
			if (item.isDirectory()) {
				results.push(...this.findMoveTomls(fullPath));
			} else if (item.name === 'Move.toml') {
				results.push(fullPath);
			}
		}

		return results;
	}

	public loadPackages(packagesRoot: string) {
		const moveTomlPaths = this.findMoveTomls(packagesRoot);

		for (const moveTomlPath of moveTomlPaths) {
			const content = fs.readFileSync(moveTomlPath, 'utf8');
			const parsed = TOML.parse(content);

			if (!(parsed.package as any).name) continue;

			const dependencies: string[] = [];
			if (parsed.dependencies) {
				for (const [depName, depInfo] of Object.entries(parsed.dependencies)) {
					if (typeof depInfo === 'object' && 'local' in depInfo) {
						dependencies.push(depName);
					}
				}
			}
			this.packages.set((parsed.package as any).name, {
				name: (parsed.package as any).name,
				path: path.dirname(moveTomlPath),
				dependencies,
				published: false
			});
		}
	}

	private getPublishOrder(): string[] {
		const visited = new Set<string>();
		const order: string[] = [];

		const visit = (packageName: string) => {
			if (visited.has(packageName)) return;
			visited.add(packageName);

			const pkg = this.packages.get(packageName);
			if (!pkg) return;

			for (const dep of pkg.dependencies) {
				visit(dep);
			}
			order.push(packageName);
		};

		for (const packageName of this.packages.keys()) {
			visit(packageName);
		}

		return order;
	}

	private async publishPackage(packageInfo: Package): Promise<string> {
		console.log(`\n📦 Publishing package: ${packageInfo.name}`);

		// Delete Move.lock
		const moveLockPath = path.join(packageInfo.path, 'Move.lock');
		if (fs.existsSync(moveLockPath)) {
			fs.unlinkSync(moveLockPath);
			console.log("Deleted Move.lock file");
		}

		// Update Move.toml
		const moveTomlPath = path.join(packageInfo.path, 'Move.toml');
		const namedAddress = packageInfo.name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

		const moveTomlContent = fs.readFileSync(moveTomlPath, 'utf8');
		const parsedToml = TOML.parse(moveTomlContent);

		if (!parsedToml.addresses) {
			throw new Error(`${packageInfo.name} Move.toml does not contain addresses section`);
		}
		// change named address to 0x0 before publish
		(parsedToml.addresses as any)[namedAddress] = "0x0";
		fs.writeFileSync(moveTomlPath, TOML.stringify(parsedToml));

		// Build package
		console.log("Building package...");
		const { modules, dependencies } = JSON.parse(
			execSync(
				`${process.env.CLI_PATH!} move build --dump-bytecode-as-base64 --path ${packageInfo.path}`,
				{ encoding: "utf-8" }
			)
		);

		// Publish package
		console.log("Publishing...");
		const tx = new Transaction();
		tx.setGasBudget(1000000000);

		const [upgradeCap] = tx.publish({ modules, dependencies });
		tx.transferObjects([upgradeCap], keypair.getPublicKey().toSuiAddress());

		const result = await client.signAndExecuteTransaction({
			signer: keypair,
			transaction: tx,
			options: {
				showObjectChanges: true,
				showEffects: true,
			},
			requestType: "WaitForLocalExecution"
		});

		if (result.effects?.status?.status !== "success") {
			throw new Error(`Publish failed: ${result.effects?.status?.error}`);
		}

		const packageId = result.objectChanges?.find((item: SuiObjectChange) => item.type === 'published')?.packageId;

		if (!packageId) {
			throw new Error("Could not find package ID in publish result");
		}

		// Save publish info
		const objects: IObjectInfo[] = result.objectChanges!.map((item: SuiObjectChange) => ({
			type: item.type === 'published' ? packageInfo.name : item.objectType,
			id: item.type === 'published' ? item.packageId : item.objectId
		}));

		const dataDir = path.join(__dirname, "./data");
		if (!fs.existsSync(dataDir)) {
			fs.mkdirSync(dataDir, { recursive: true });
		}
		fs.writeFileSync(
			`${dataDir}/${namedAddress.replace("_", "-")}.json`,
			JSON.stringify(objects, null, 2)
		);

		// Update Move.lock
		execSync(
			`${process.env.CLI_PATH!} move manage-package --environment "$(sui client active-env)" \
			--network-id "$(sui client chain-identifier)" \
			--original-id ${packageId} \
			--latest-id ${packageId} \
			--version-number "1" \
			--path ${packageInfo.path}`,
			{ encoding: "utf-8" }
		);

		// Update Move.toml files (both the package itself and its dependents)
		for (const pkg of this.packages.values()) {
			// Skip if it's not the package itself and doesn't depend on it
			if (pkg.name !== packageInfo.name && !pkg.dependencies.includes(packageInfo.name)) {
				continue;
			}

			const pkgMoveToml = path.join(pkg.path, 'Move.toml');
			const content = fs.readFileSync(pkgMoveToml, 'utf8');
			const parsed = TOML.parse(content);

			if (parsed.addresses && typeof parsed.addresses === 'object') {
				(parsed.addresses as Record<string, string>)[namedAddress] = packageId;
				fs.writeFileSync(pkgMoveToml, TOML.stringify(parsed));
				console.log(`Updated ${pkg.name}'s Move.toml with ${packageInfo.name}'s address`);
			}
		}

		console.log("\x1b[32m" + `\n✅ Successfully published ${packageInfo.name} at: ${packageId}` + "\x1b[0m");
		return packageId;
	}

	public async publishAll(): Promise<boolean> {
		if (this.packages.size === 0) {
			console.log("Packages not loaded");
			return false;
		}

		const confirmed = await this.confirmPublish();
		if (!confirmed) {
			console.log("Publish cancelled");
			return false;
		}

		const order = this.getPublishOrder();
		console.log("\n📋 Publish order:", order.join(" → "));

		for (const packageName of order) {
			const pkg = this.packages.get(packageName)!;
			try {
				await this.publishPackage(pkg);
				pkg.published = true;
			} catch (error) {
				console.error(`\n❌ Failed to publish ${packageName}:`, error);
				break;
			}
		}

		const successful = Array.from(this.packages.values()).filter(p => p.published).map(p => p.name);
		const failed = Array.from(this.packages.values()).filter(p => !p.published).map(p => p.name);

		console.log("\n📊 Publish Summary:");
		if (successful.length > 0) {
			console.log("✅ Successfully published:", successful.join(", "));
		}
		if (failed.length > 0) {
			console.log("❌ Failed to publish:", failed.join(", "));
			return false;
		}

		return true;
	}
}