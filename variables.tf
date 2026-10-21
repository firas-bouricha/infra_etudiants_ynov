# Valeurs données via .env (TF_VAR_nom) ou equipes.auto.tfvars

variable "proxmox_endpoint" {
  description = "Adresse de l'API Proxmox, ex : https://192.168.137.129:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "Jeton API : utilisateur@pve!nom=secret"
  type        = string
  sensitive   = true
}

variable "student_password" {
  description = "Mot de passe initial des comptes étudiants (à changer à la première connexion)"
  type        = string
  sensitive   = true
}

variable "node_name" {
  description = "Nom du noeud Proxmox (affiché dans l'arbre de l'interface)"
  type        = string
  default     = "pve"
}

variable "storages" {
  description = "Stockages utilisables par les étudiants (disques de VM et ISO)"
  type        = list(string)
  default     = ["local", "local-lvm"]
}

variable "teams" {
  description = "Équipes : nom (3 à 6 lettres/chiffres) => liste des étudiants"
  type        = map(list(string))
}
