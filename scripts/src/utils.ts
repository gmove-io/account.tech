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

export const client = new SuiClient({ url: "https://sui-testnet-endpoint.blockvision.org" });

export const getId = (type: string): string => {
    const extensionsData = fs.readFileSync('./src/data/extensions-created.json', 'utf8');
    const extensionsParsed: IObjectInfo[] = JSON.parse(extensionsData);
    const actionsData = fs.readFileSync('./src/data/actions-created.json', 'utf8');
    const actionsParsed: IObjectInfo[] = JSON.parse(actionsData);
    const multisigData = fs.readFileSync('./src/data/multisig-created.json', 'utf8');
    const multisigParsed: IObjectInfo[] = JSON.parse(multisigData);

    const parsed = [...extensionsParsed, ...actionsParsed, ...multisigParsed];
    const typeToId = new Map(parsed.map(item => [item.type, item.id]));
    // Find the first key that starts with the type
    for (let [key, value] of typeToId) {
        if (key?.startsWith(type)) {
            if (value === undefined) {
                throw new Error(`Value for ${type} is undefined`);
            }
            return value;
        }
    }
    throw new Error(`Type ${type} not found in *-created.json`);
}