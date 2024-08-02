# How to use the Deployment Scripts

## Deploy the protocol Foundation

Use DeploymentScript.s.sol to deploy the protocol foundation. We can run it with the following command:

```
forge script script/deploymentScript/DeploymentScript.s.sol
```

## Deploy a new standalone module

For this usecase we use the CreateAndDeployModuleBeacon.s.sol script. We can run it with the following command:

```
forge script script/utils/CreateAndDeployModuleBeacon.s.sol "run(string,string,address,address,uint,uint,uint)" "ExampleModule" "src/module/ExampleModule.sol" "0x0000000000000000000000000000000000000001" "0x0000000000000000000000000000000000000002" 1 0 0
```

## Add a new module to the deployment script

For us to a add a new module to the deployment script, we need to:

1. Add the module metadata to the MetadataCollection_v1.s.sol
2. Add the module implementation to the SingletonDeployer_v1.s.sol
3. Add the module beacon to the ModuleBeaconDeployer_v1.s.sol
