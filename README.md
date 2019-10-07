
# Write Secrets

Generate LetsEncrypt signed certificates and upload as secrets to Key Vault.
NOTE:  This extension is not affiliated with LetsEncrypt or the EFF.

## Getting Started
As of this writing, automated certificate generation is possible using Azure's Key Vault and two, public certificate authorities.  However, integration with the Electronic Frontier Foundation's LetsEncrypt certificate authority is not yet available or planned.  This extension fills that gap by enabling the acquisition of signed certificates from LetsEncrypt and uploading them to an Azure Key Vault.

This extension is merely a front end for portions of Ryan's Bolger's Posh-ACME module (https://github.com/rmbolger/Posh-ACME).  It is intended to be part of a task group where a certificate is requested, stored in Key Vault and subsequent tasks or builds download the key/cert from Key Vault.  Toward that end, the extension supports tagging the Key Vault secret so that other tasks can identify the certificate.  Tagging is also useful to identify where the certificate is installed to add visibily and tracking information for renewals.

This extension requires a custom Powershell module, you may run it on private (not hosted) VSTS agents, but if you wish to use an Azure hosted agent you will need to run this command first in the pipeline to install the Posh-ACME module:

**Install-Module -Name Posh-ACME -force -Scope CurrentUser**

Also, since there's no guarantee that this extension will always run on the same VSTS agent, it does not make sense to maintain a local history of each request.  Doing so would keep certificates in a local users appdata folder, which is harder to secure and maintain than storing them in Key Vault.  Therefore, this extension sets the $env:LOCALAPPDATA variable to the VSTS variable BUILD_STAGINGDIRECTORY.  This ensures that all certificates, requests, keys, etc. are deleted at the end of each build.


### Key Vault integration
Presently, some ARM templates are unable to integrate seamlessly with Azure's Key Vault.  Perhaps this is just my experience, but I've seen that some ARM templates are able to query Key Vault for a certificate (i.e. NOT a secret), while others require a pfx file.  I've found that Powershell works well as an intermediary to make certificate management more consistent across resource types.  Therefore, this extension offers several options on how to store the certificate in Key Vault.  It can store certificates as base64-encoded, password-protected secrets, or as keys, or as certificates.  There are other VSTS extensions that can retrieve and decrypt these secrets for use in VSTS tasks. 

### Prerequisites
This extension requires Ryan Bolger's Posh-ACME module https://github.com/rmbolger/Posh-ACME.  This extension has been tested with version 2.0.1 of this module.

## Configuration


## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags). 

## Authors

* Craig Boroson 

See also the list of [contributors](https://github.com/cboroson/VSTS-LetsEncrypt/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* Ryan Bolger for his fantastic work in creating the Posh-ACME module
