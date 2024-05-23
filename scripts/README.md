# sui-interaction-scripts
TS scripts for deploying and calling Sui packages.

### Get Started
- rename `.env.example` to `.env` and modify the variables
- install bun: `curl -fsSL https://bun.sh/install | bash`
- run `bun install`
- deploy: `bun run publish`
- call: `bun run call`

### Commands
Modify `package.json` scripts according to the interaction files you create.
You can create a separate call_function_name file for each of the functions in your package.

### Get Object IDs
The publish script automatically write the object IDs that your package creates on init in a `created.json` file. Feel free to extend it to other constructor functions you may have.
You can then directly read object IDs from the json file with `getId("module_name::type_name")` from ./utils.