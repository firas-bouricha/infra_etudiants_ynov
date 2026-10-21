# Lab Proxmox pour les étudiants

Ce dépôt crée automatiquement, pour chaque équipe d'étudiants :

- **un compte Proxmox par étudiant** ;
- **un espace à elle** (un « pool ») : l'équipe voit et gère ses VM, jamais celles des autres ;
- **un réseau déjà prêt**, séparé de celui des autres équipes.

Tout est décrit dans 3 fichiers Terraform courts, commentés ligne par ligne.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `equipes.auto.tfvars` | **Le seul à modifier** : la liste des équipes et des étudiants |
| `.env.example` | Modèle pour tes secrets (adresse, jeton, mot de passe) |
| `main.tf` | Crée pools, comptes, droits et réseaux |
| `variables.tf` | Liste des paramètres |
| `provider.tf` | Connexion à Proxmox |

## Ce que reçoit chaque équipe

| Élément | Exemple pour `eq01` | À quoi ça sert |
|---|---|---|
| Comptes | `alice@pve`, `bob@pve` | Connexion à l'interface Proxmox |
| Pool | `eq01` | Contient les VM de l'équipe |
| Réseau WAN | `eq01w` — `172.16.1.0/24`, passerelle `172.16.1.1` | Sortie Internet (NAT) |
| Réseau LAN | `eq01l` | Réseau interne, sans sortie, compatible VLAN |

Les réseaux des équipes sont numérotés dans l'ordre : `eq01` → `172.16.1.0/24`,
`eq02` → `172.16.2.0/24`, etc.

**Pour un OPNsense** : carte 1 sur `eq01w` (WAN), carte 2 sur `eq01l` (LAN).
Sur le WAN, configurer l'IP `172.16.1.2/24`, passerelle `172.16.1.1`, DNS `1.1.1.1`.

## Utilisation

### Étape 1 — Créer un jeton API sur Proxmox (une seule fois)

Dans la console du serveur Proxmox :

```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role PVEAdmin
pveum user token add terraform@pve tf --privsep 0
```

Le secret s'affiche **une seule fois** : copie-le.

### Étape 2 — Installer Terraform sur ton PC

Sur Ubuntu : voir https://developer.hashicorp.com/terraform/install
Ton PC doit pouvoir joindre le Proxmox (port 8006).

### Étape 3 — Remplir le fichier `.env`

```bash
cp .env.example .env
nano .env          # adresse, jeton, mot de passe initial
source .env        # charge les valeurs (à refaire à chaque nouveau terminal)
```

### Étape 4 — Choisir les équipes

Ouvre `equipes.auto.tfvars` et écris les équipes et les étudiants.

### Étape 5 — Lancer

```bash
terraform init     # télécharge le module Proxmox (une seule fois)
terraform plan     # montre ce qui va être créé, sans rien faire
terraform apply    # crée tout (répondre "yes")
```

Commence avec **une équipe de test**, vérifie, puis ajoute les autres.

### Étape 6 — Donner l'accès aux étudiants

Remets à chaque étudiant :

- l'adresse : `https://IP-DU-SERVEUR:8006` (accepter l'avertissement de certificat) ;
- son identifiant : `alice` ;
- le domaine : **Proxmox VE authentication server** ;
- le mot de passe initial, à changer à la première connexion.

## Vérifier que ça marche

1. Ouvre une fenêtre de navigation privée.
2. Connecte-toi avec un compte étudiant (domaine « Proxmox VE authentication server »).
3. Il doit voir **seulement le pool de son équipe**.
4. Connecte-toi avec un compte d'une autre équipe : il ne doit pas voir les mêmes VM.

## Opérations courantes

| Je veux… | Je fais… |
|---|---|
| Ajouter une équipe ou un étudiant | Modifier `equipes.auto.tfvars`, puis `terraform apply` |
| Supprimer une équipe | La retirer du fichier, puis `terraform apply` (supprime comptes, pool, réseaux) |
| Voir ce qui existe | `terraform state list` |
| Tout supprimer | `terraform destroy` |

Avant de supprimer une équipe, supprime d'abord ses VM dans Proxmox : un pool non vide ne peut pas être effacé.

## À savoir

- **Ressources du serveur** : les étudiants peuvent créer des VM. Prévois environ 16 Go de RAM par équipe en parcours Linux, et surveille le serveur.
- **Fichier d'état** : `terraform.tfstate` (créé après `apply`) contient le mot de passe initial. Ne le publie pas : le `.gitignore` l'exclut déjà.
- **Premier `apply`** : si Terraform signale une erreur sur un nom de ressource réseau (SDN), vérifie la documentation du module `bpg/proxmox` pour ta version : https://registry.terraform.io/providers/bpg/proxmox/latest/docs
- **Rôles** : `PVEVMAdmin`, `PVEDatastoreUser` et `PVESDNUser` existent déjà dans Proxmox (Datacenter → Permissions → Roles).
- **Réseau de l'école** : ce lab est prévu pour l'usage interne des étudiants ; aucune règle de filtrage vers le Wi-Fi de l'école n'est ajoutée.

## Publier sur GitHub

```bash
git init
git add .
git commit -m "Lab Proxmox étudiants"
git branch -M main
git remote add origin https://github.com/TON-COMPTE/lab-proxmox.git
git push -u origin main
```

Vérifie avant le `git add` que `.env` n'apparaît pas dans `git status`.
