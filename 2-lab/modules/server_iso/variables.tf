variable "url" {
  type = string
}

variable "path" {
  description = "Where the ISO is written on the server"
  type        = string
}

variable "sha256" {
  description = "Checksum of the downloaded file, when the publisher gives one"
  type        = string
  default     = null
}

variable "gzip" {
  description = "The download is gzipped: unpacked on the server"
  type        = bool
  default     = false
}

variable "server" {
  description = "SSH access to the server (sudo)"
  type = object({
    host             = string
    user             = string
    private_key_path = string
  })
}
