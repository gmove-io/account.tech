import { getFullnodeUrl, SuiClient } from '@mysten/sui.js/client';
import { Ed25519Keypair } from '@mysten/sui.js/keypairs/ed25519';
import dotenv from "dotenv";
import * as fs from "fs";

export interface IObjectInfo {
    type: string | undefined
	id: string | undefined
}

dotenv.config();

export const keypair = Ed25519Keypair.fromSecretKey(Uint8Array.from(Buffer.from(process.env.KEY!, "base64")).slice(1));

export const client = new SuiClient({ url: "https://sui-testnet-endpoint.blockvision.org" });

export const getId = (type: string): string | undefined => {
    try {
        const rawData = fs.readFileSync('./created.json', 'utf8');
        const parsedData: IObjectInfo[] = JSON.parse(rawData);
        const typeToId = new Map(parsedData.map(item => [item.type, item.id]));
        for (let [key, value] of typeToId) {
            if (key && key.startsWith(type)) {
                return value;
            } 
        }
    } catch (error) {
        console.error('Error reading the created file:', error);
    }
}