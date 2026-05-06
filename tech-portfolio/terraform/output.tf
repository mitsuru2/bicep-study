output "client_id" {
  value = azuread_application.app.client_id
}

output "principal_id" {
  value = azuread_service_principal.sp.object_id
}