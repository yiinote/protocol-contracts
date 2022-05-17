const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const ImmutableToken = artifacts.require('ImmutableToken');

const mainnet = {
	imx: "0x5FDCCA53617f4d2b9134B29090C87D01058e27e9"
}
const ropsten = {
	imx: "0x4527be8f31e2ebfbef4fcaddb5a17447b27d2aef"
}

let settings = {
	"ropsten": ropsten,
	"mainnet": mainnet
};

function getSettings(network) {
	if (settings[network] !== undefined) {
		return settings[network];
	} else {
		return settings["default"];
	}
}

module.exports = async function (deployer, network) {
  const settings = getSettings(network)

  await deployer.deploy(ImmutableToken, "testImmutableX", "TIX", settings.imx, { gas: 5000000 });

  const token = await ImmutableToken.deployed();

  console.log(token.address, "immutable token")
};

