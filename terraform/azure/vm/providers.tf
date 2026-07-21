# The Torque agent injects Azure credentials (ARM_*) as environment variables.
# Only the mandatory features block is configured here.
provider "azurerm" {
  features {}
}
