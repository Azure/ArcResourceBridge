# Arc Resource Bridge

Azure Arc Resource Bridge is part of the core Azure Arc platform, and is designed to host other Azure Arc services.  This repository contains relevant resources for administering Azure Arc resource bridge (preview).

NOTE: Any resources here might still be in development and should only be used after consulting relevant documentation.

Learn more: [Arc resource bridge](https://docs.microsoft.com/en-us/azure/azure-arc/resource-bridge/overview)

## [Disaster Recovery](./Disaster_Recovery)

In disaster scenarios for the Arc resource bridge (i.e. accidental deletion or hardware failure), disaster recovery is a last-resort method to recreate a healthy Arc resource bridge and restore the original state of the user's Arc-enabled Vmware system.

The Disaster_Recovery folder contains an in-development PowerShell script that supports this process for Arc-enabled VMware only.  Once again, consult the relevant documentation linked above before running.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
