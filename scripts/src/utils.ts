import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import dotenv from "dotenv";
import * as fs from "fs";

export interface IObjectInfo {
    type: string | undefined
	id: string | undefined
}

dotenv.config();

export const keypair = Ed25519Keypair.fromSecretKey(Uint8Array.from(Buffer.from(process.env.KEY!, "base64")).slice(1));

export const client = new SuiClient({ url: getFullnodeUrl(process.env.NETWORK as "mainnet" | "testnet" | "devnet" | "localnet") });

export const getId = (type: string, isMainnet: boolean = false): string => {
    const dataDir = isMainnet ? "./src/mainnet-data/" : "./src/testnet-data/";
    const allObjects: IObjectInfo[] = [];

    fs.readdirSync(dataDir)
        .forEach(file => {
            try {
                const fileData = fs.readFileSync(`${dataDir}${file}`, 'utf8');
                allObjects.push(...JSON.parse(fileData));
            } catch (error) {
                console.error(`Error reading or parsing ${file}: ${error}`);
            }
        });

    const matchingObject = allObjects.find(item => item.type?.startsWith(type));
    
    if (!matchingObject || matchingObject.id === undefined) {
        throw new Error(`Type ${type} not found or has undefined id in ${dataDir}`);
    }

    return matchingObject.id;
}