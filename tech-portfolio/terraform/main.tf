terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azuread" {}

variable "app_name" {
  type        = string
  description = "The display name of the Azure AD application"
}

variable "github_org" {
  type        = string
  description = "The GitHub organization or user name"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository name"
}

# アプリケーション登録
resource "azuread_application" "app" {
  display_name = var.app_name
}

# サービスプリンシパル
resource "azuread_service_principal" "sp" {
  client_id = azuread_application.app.client_id
}

# OIDCフェデレーション資格情報
resource "azuread_application_federated_identity_credential" "oidc_main" {
  application_id = azuread_application.app.id
  display_name   = "github-oidc-main"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
  audiences      = ["api://AzureADTokenExchange"]
}
resource "azuread_application_federated_identity_credential" "oidc_restricted" {
  application_id = azuread_application.app.id
  display_name   = "github-oidc-restricted"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:environment:restricted"
  audiences      = ["api://AzureADTokenExchange"]
}
