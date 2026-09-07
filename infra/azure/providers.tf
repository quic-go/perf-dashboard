provider "azurerm" {
  subscription_id = var.azure_subscription_id

  features {
    # keep partially created resources in state so destroy can remove them
    persist_id_on_create_before_polling_for_completion = true

    virtual_machine {
      skip_shutdown_and_force_delete = true
    }
  }
}
