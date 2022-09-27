const os = require('os');

let apiKey;
try {
	console.log(`Loading etherscan key from ${os.homedir() + "/.ethereum/etherscan.json"}`);
	apiKey = require(os.homedir() + "/.ethereum/etherscan.json").apiKey;
	console.log("loaded etherscan api key");
} catch {
	console.log("unable to load etherscan key from config")
	apiKey = "UNKNOWN"
}

function createNetwork(name) {
  try {
    console.log('createNetwork', name);
    var json = require(os.homedir() + "/.ethereum/" + name + ".json");
    var gasPrice = json.gasPrice != null ? json.gasPrice : 2000000000;

    return {
      provider: () => {
        const { estimate } = require("@rarible/estimate-middleware")
	      if (json.path != null) {
	        const { createProvider: createTrezorProvider } = require("@rarible/trezor-provider")
	        const provider = createTrezorProvider({ url: json.url, path: json.path, chainId: json.network_id })
	        provider.send = provider.sendAsync
	        return provider
	      } else {
	        return createProvider(json.address, json.key, json.url)
	      }
      },
      from: json.address,
      gas: 8000000,
      // gasPrice: gasPrice + "000000000",
      gasPrice: gasPrice,
      network_id: json.network_id,
      skipDryRun: true,
      networkCheckTimeout: 5000000,
      timeoutBlocks: 200
    };
  } catch (e) {
    return null;
  }
}

function createProvider(address, key, url) {
  console.log("creating provider for address: " + address);
  var HDWalletProvider = require("@truffle/hdwallet-provider");
  return new HDWalletProvider(key, url);
}

module.exports = {
	api_keys: {
    etherscan: apiKey
  },

	plugins: [
    'truffle-plugin-verify',
    'truffle-contract-size'
  ],

  networks: {
    e2e: createNetwork("e2e"),
    ops: createNetwork("ops"),
    ropsten: createNetwork("ropsten"),
    mainnet: createNetwork("mainnet"),
    rinkeby: createNetwork("rinkeby"),
    rinkeby2: createNetwork("rinkeby2"),
    polygon_mumbai: createNetwork("polygon_mumbai"),
    polygon_mainnet: createNetwork("polygon_mainnet"),
    polygon_dev: createNetwork("polygon_dev"),
    dev: createNetwork("dev"),
    goerli: createNetwork("goerli"),
    staging: createNetwork("staging"),
    polygon_staging: createNetwork("polygon_staging"),
    ganache: createNetwork("ganache"),
  },

  compilers: {
    solc: {
      version: "0.7.6",
      settings: {
        optimizer: {
          enabled : true,
          runs: 200
        },
        evmVersion: "istanbul"
      }
    }
  }
}

console.log('exports', module.exports)