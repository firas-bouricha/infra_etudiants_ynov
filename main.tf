# Pour chaque équipe, ce fichier crée :
#   1. un pool    : le "dossier" qui contiendra ses VM
#   2. un groupe  : l'équipe
#   3. des comptes: un par étudiant
#   4. des droits : l'équipe gère SES VM, et ne voit pas celles des autres
#   5. un réseau  : isolé des autres équipes (voir README)

locals {
  # Liste triée des équipes. Sert à numéroter les réseaux : eq01 -> 1, eq02 -> 2...
  noms_equipes = sort(keys(var.teams))
  numero       = { for i, nom in local.noms_equipes : nom => i + 1 }

  # Un élément par étudiant : { alice = "eq01", bob = "eq01", ... }
  etudiants = merge([
    for equipe, membres in var.teams : { for m in membres : m => equipe }
  ]...)
}

# 1. Pool : les VM de l'équipe seront rangées ici
resource "proxmox_virtual_environment_pool" "equipe" {
  for_each = var.teams
  pool_id  = each.key
}

# 2. Groupe : sert à donner les droits à toute l'équipe d'un coup
resource "proxmox_virtual_environment_group" "equipe" {
  for_each = var.teams
  group_id = each.key
}

# 3. Comptes étudiants (connexion : alice@pve, domaine "Proxmox VE authentication server")
resource "proxmox_virtual_environment_user" "etudiant" {
  for_each = local.etudiants

  user_id  = "${each.key}@pve"
  password = var.student_password
  groups   = [proxmox_virtual_environment_group.equipe[each.value].group_id]
}

# 4a. Droits sur le pool : gérer ses VM (créer, configurer, console, snapshots)
#     Un groupe ne voit que les pools où il a des droits.
resource "proxmox_virtual_environment_acl" "pool" {
  for_each = var.teams

  path      = "/pool/${each.key}"
  role_id   = "PVEVMAdmin"
  group_id  = proxmox_virtual_environment_group.equipe[each.key].group_id
  propagate = true
}

# 4b. Droits sur le stockage : nécessaires pour créer des disques et lire les ISO.
#     (équipes x stockages)
resource "proxmox_virtual_environment_acl" "stockage" {
  for_each = {
    for p in setproduct(keys(var.teams), var.storages) : "${p[0]}-${p[1]}" => p
  }

  path      = "/storage/${each.value[1]}"
  role_id   = "PVEDatastoreUser"
  group_id  = proxmox_virtual_environment_group.equipe[each.value[0]].group_id
  propagate = true
}

# 5. Réseau : une zone par équipe, avec deux réseaux virtuels
#    <equipe>w = WAN : sort sur Internet (NAT), adresses 172.16.N.0/24
#    <equipe>l = LAN : réseau interne de l'équipe, sans sortie
resource "proxmox_virtual_environment_sdn_zone_simple" "equipe" {
  for_each = var.teams

  id    = each.key
  nodes = [var.node_name]
}

resource "proxmox_virtual_environment_sdn_vnet" "wan" {
  for_each = var.teams

  id   = "${each.key}w"
  zone = proxmox_virtual_environment_sdn_zone_simple.equipe[each.key].id
}

resource "proxmox_virtual_environment_sdn_vnet" "lan" {
  for_each = var.teams

  id         = "${each.key}l"
  zone       = proxmox_virtual_environment_sdn_zone_simple.equipe[each.key].id
  vlan_aware = true # permet de créer des VLAN (zones RH, Compta...) dans OPNsense
}

resource "proxmox_virtual_environment_sdn_subnet" "wan" {
  for_each = var.teams

  vnet    = proxmox_virtual_environment_sdn_vnet.wan[each.key].id
  cidr    = "172.16.${local.numero[each.key]}.0/24"
  gateway = "172.16.${local.numero[each.key]}.1"
  snat    = true # partage la connexion Internet du serveur
}

# 5b. Droit d'utiliser SES réseaux (et seulement ceux-là) pour brancher ses VM
resource "proxmox_virtual_environment_acl" "reseau_wan" {
  for_each = var.teams

  path      = "/sdn/zones/${each.key}/${each.key}w"
  role_id   = "PVESDNUser"
  group_id  = proxmox_virtual_environment_group.equipe[each.key].group_id
  propagate = true

  depends_on = [proxmox_virtual_environment_sdn_vnet.wan]
}

resource "proxmox_virtual_environment_acl" "reseau_lan" {
  for_each = var.teams

  path      = "/sdn/zones/${each.key}/${each.key}l"
  role_id   = "PVESDNUser"
  group_id  = proxmox_virtual_environment_group.equipe[each.key].group_id
  propagate = true

  depends_on = [proxmox_virtual_environment_sdn_vnet.lan]
}

# Applique la configuration réseau (équivalent du bouton "Apply" dans Datacenter > SDN)
resource "proxmox_virtual_environment_sdn_applier" "appliquer" {
  depends_on = [
    proxmox_virtual_environment_sdn_zone_simple.equipe,
    proxmox_virtual_environment_sdn_vnet.wan,
    proxmox_virtual_environment_sdn_vnet.lan,
    proxmox_virtual_environment_sdn_subnet.wan,
  ]

  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_zone_simple.equipe,
      proxmox_virtual_environment_sdn_vnet.wan,
      proxmox_virtual_environment_sdn_vnet.lan,
      proxmox_virtual_environment_sdn_subnet.wan,
    ]
  }
}
