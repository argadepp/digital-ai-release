variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-dai-demo-dev"
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Azure Resource Group names must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for the Resource Group"
  type        = string
  default     = "Central India"
}

variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "DEV"
}
