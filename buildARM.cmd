az bicep build --file main.bicep --outfile azuredeploy.json

az bicep generate-params --file main.bicep --outfile azuredeploy.parameters.json