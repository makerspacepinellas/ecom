variable "app_name" {
  type    = string
  default = "ecom"
}
variable "owner_name" {
  type = string
  default = "websites"
}
variable "root_domain" {
  type    = string
  default = "ecom.makerspacepinellas.org"
}
variable "create_api_domain_name" {
  type = bool
  default = false
}