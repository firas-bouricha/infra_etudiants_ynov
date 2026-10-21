# Connexion à Proxmox.
# Les valeurs viennent du fichier .env (voir .env.example), jamais écrites ici.

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # Proxmox utilise un certificat auto-signé
}
