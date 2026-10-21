# Lab Proxmox pour les étudiants

Ce dépôt crée automatiquement, pour chaque équipe d'étudiants :

- **un compte Proxmox par étudiant** ;
- **un espace à elle** (un « pool ») : l'équipe voit et gère ses VM, jamais celles des autres ;
- **un réseau déjà prêt**, séparé de celui des autres équipes.

Le README a deux parties : **A. Administrateur** (toi) et **B. Guide étudiants** (à donner aux équipes).

---

# A. Administrateur

## Les fichiers

| Fichier | Rôle |
|---|---|
| `equipes.auto.tfvars` | **Le seul à modifier** : équipes, étudiants, stockages |
| `.env.example` | Modèle pour tes secrets (adresse, jeton, mot de passe) |
| `main.tf` | Crée pools, comptes, droits et réseaux |
| `variables.tf` | Liste des paramètres |
| `provider.tf` | Connexion à Proxmox |

## Ce que reçoit chaque équipe

| Élément | Exemple pour `eq01` | À quoi ça sert |
|---|---|---|
| Comptes | `chris@pve`, `andrea@pve` | Connexion à l'interface Proxmox |
| Pool | `eq01` | Contient les VM de l'équipe |
| Réseau WAN | `eq01w`, `172.16.1.0/24`, passerelle `172.16.1.1` | Sortie Internet (NAT) |
| Réseau LAN | `eq01l` (compatible VLAN) | Réseau interne de l'équipe, sans sortie |

Les équipes sont numérotées dans l'ordre alphabétique : `eq01` → N=1, `eq02` → N=2, etc.
Le réseau WAN de l'équipe N est `172.16.N.0/24`.

## Mise en place

### Étape 1 : jeton API sur Proxmox (une seule fois)

Console du serveur Proxmox :

```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve tf --privsep 0
```

Le rôle `Administrator` est nécessaire : `PVEAdmin` ne suffit pas pour gérer les droits sur les réseaux (erreur 403).
Le secret du jeton s'affiche **une seule fois** : copie-le (format final : `terraform@pve!tf=UUID`).

### Étape 2 : installer Terraform sur ton PC

https://developer.hashicorp.com/terraform/install
Ton PC doit pouvoir joindre le Proxmox (port 8006).

### Étape 3 : secrets

```bash
cp .env.example .env
nano .env          # adresse, jeton, mot de passe initial
source .env        # à refaire dans chaque nouveau terminal
```

### Étape 4 : équipes

Édite `equipes.auto.tfvars` :

```hcl
teams = {
  eq01 = ["chris", "andrea"]
  eq02 = ["chloe", "david"]
}

# Stockages visibles par les équipes (ajoute isos / vms2 si tu les as créés)
storages = ["local", "local-lvm"]
```

### Étape 5 : lancer

```bash
terraform init
terraform plan     # lire la ligne "Plan: X to add, Y to change, Z to destroy"
terraform apply
```

Pour ajouter une équipe : l'ajouter au fichier, `plan` (Y et Z doivent valoir 0), `apply`.

## Droits donnés à chaque équipe

| Où | Rôle | Pour quoi faire |
|---|---|---|
| `/pool/<équipe>` | `PVEVMAdmin` | Créer et gérer ses VM |
| `/pool/<équipe>` | `PVEPoolUser` | **Voir** son pool (sinon absent de la liste à la création d'une VM) |
| `/storage/<stockage>` | `PVEDatastoreUser` | Créer des disques, lire les ISO |
| `/sdn/zones/<équipe>/<équipe>w` et `...l` | `PVESDNUser` | Brancher ses VM sur SES réseaux seulement |

## Images ISO (visibles par toutes les équipes)

1. Arbre de gauche : **`local`** → **ISO Images** → **Upload** ou **Download from URL**.
2. Les équipes les voient à la création d'une VM (lecture seule, elles ne peuvent pas en ajouter).
3. Liste conseillée : Debian netinst, OPNsense (`dvd`, `amd64`), Windows Server (évaluation) + ISO `virtio-win`.
   OPNsense est livré en `.iso.bz2` : décompresser (`bunzip2`) avant l'upload si Proxmox ne le fait pas.

## Disques supplémentaires (sans RAID)

**Disks → Directory → Create: Directory** (formate, monte et ajoute au démarrage) :

| Disque | Nom | Contenu à cocher |
|---|---|---|
| `/dev/sdc` | `isos` | `ISO image` seulement |
| `/dev/sdd` | `vms2` | `Disk image`, `Container` |

Puis ajoute `"isos"` et `"vms2"` à `storages` dans `equipes.auto.tfvars`, et `terraform apply`.
Sans RAID : un disque qui tombe fait perdre ses données.

## Accès des étudiants : Tailscale

1. Installer Tailscale sur le Proxmox (console) :
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   tailscale up --hostname=pve-ynov
   ```
   Si `apt update` échoue (erreur 401 `enterprise.proxmox.com`) : désactiver les dépôts payants et ajouter `pve-no-subscription`.
2. Se connecter avec un compte **personnel** (pas l'e-mail de l'école : il rejoindrait le réseau de l'école sans droits d'administration).
3. Console https://login.tailscale.com/admin/machines → `pve-ynov` → `⋯` → **Disable key expiry**.
4. **Partage** : `⋯` → **Share…** → invitation à chaque étudiant (ils ne voient que cette machine).
5. Limiter l'accès au port 8006 depuis Tailscale :
   ```bash
   iptables -A INPUT -i tailscale0 -p tcp --dport 8006 -j ACCEPT
   iptables -A INPUT -i tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT
   iptables -A INPUT -i tailscale0 -j DROP
   apt install iptables-persistent && netfilter-persistent save
   ```
6. Vérifier les limites du plan gratuit : https://tailscale.com/pricing

## Quotas

Proxmox n'a pas de quota par pool pour le CPU, la RAM ou le disque. Pour les limiter :
stockage dédié de taille fixe par équipe, ou VM créées par toi avec un rôle sans droits d'allocation.
Compte environ 16 Go de RAM par équipe (parcours Linux) et surveille l'utilisation du serveur.

## Dépannage

| Message / symptôme | Cause | Solution |
|---|---|---|
| `Permission check failed (/vms/100, VM.Allocate)` | Aucun pool choisi | General → **Resource Pool** = l'équipe |
| `(/sdn/zones/localnetwork/vmbr0, SDN.Use)` | Bridge `vmbr0` | Network → bridge = `<équipe>w` ou `<équipe>l` |
| `(/storage/xxx, Datastore.AllocateSpace)` | Stockage non autorisé | L'ajouter à `storages`, puis `terraform apply` |
| Liste **Resource Pool** vide | Droit `Pool.Audit` manquant | Rôle `PVEPoolUser` sur le pool (déjà dans `main.tf`) |
| `apply` : 403 `Permissions.Modify` sur `/sdn/...` | Jeton sans assez de droits | Rôle `Administrator` pour `terraform@pve` |

Contrôler les droits d'un étudiant : `pveum user permissions chris@pve`.

## À savoir

- `terraform.tfstate` contient le mot de passe initial : ne jamais le publier ; en faire une **copie de sauvegarde**.
- Ne jamais lancer `terraform destroy` : supprime comptes, droits et réseaux de toutes les équipes.
- Les VM créées à la main ne sont pas gérées par Terraform : l'ajout d'une équipe ne les touche pas.
- Dépôt GitHub **privé** (il contient des noms d'étudiants). Vérifier avant un push : `git status` ne doit lister ni `.env` ni `terraform.tfstate`.

---

# B. Guide étudiants

## 1. Se connecter

1. Installer Tailscale, ouvrir le lien d'invitation reçu, accepter le partage de `pve-ynov`.
2. Ouvrir `https://ADRESSE-DONNEE-PAR-LE-MENTOR:8006` (accepter l'avertissement de certificat).
3. Identifiant : ton prénom (ex : `chris`). Domaine : **Proxmox VE authentication server**.
4. Changer le mot de passe initial à la première connexion.

## 2. Règles pour créer une VM (assistant « Create VM »)

| Onglet | Choisir | Pourquoi |
|---|---|---|
| General | **Resource Pool = ton équipe** (ex : `eq01`) | Sans pool : erreur 403 |
| General | Nom : `eq01-role` (ex : `eq01-opnsense`) | Se retrouver dans la liste |
| OS | ISO dans `local` (ou `isos`) | Images fournies |
| Disks | Stockage `local-lvm` (ou `vms2`) | Ne pas choisir un autre |
| Network | Bridge = `<équipe>w` ou `<équipe>l` | **Jamais `vmbr0`** |

Tailles conseillées :

| VM | vCPU | RAM | Disque |
|---|---|---|---|
| OPNsense | 2 | 2 Go | 20 Go |
| Serveur Debian (annuaire, fichiers, web, sauvegarde) | 1 | 1,5 à 2 Go | 20 à 40 Go |
| Poste client | 1 | 2 Go | 20 Go |
| Windows Server (parcours A) | 2 | 4 Go | 50 Go |

Le serveur est partagé : ne dépasse pas environ 16 Go de RAM pour toute l'équipe et **éteins les VM que tu n'utilises pas**.

## 3. Plan d'adressage (N = numéro de ton équipe : `eq01` → 1, `eq02` → 2...)

### Réseau WAN (sortie Internet) : bridge `<équipe>w`

| Élément | Valeur |
|---|---|
| Réseau | `172.16.N.0/24` |
| Passerelle (le serveur) | `172.16.N.1` |
| **WAN d'OPNsense** | **`172.16.N.2/24`**, passerelle `172.16.N.1` |
| DNS | `1.1.1.1` |

Exemple équipe `eq01` : WAN OPNsense = `172.16.1.2/24`, passerelle `172.16.1.1`.
Les IP du WAN sont **fixes** (pas de DHCP). Seule la VM OPNsense est branchée au WAN.

### Réseau LAN (interne) : bridge `<équipe>l`, avec VLAN

Le réseau interne utilise `10.10.0.0/16`. Chaque zone du projet est un VLAN, créé dans OPNsense :

| Zone | VLAN | Réseau | Passerelle (OPNsense) |
|---|---|---|---|
| Admin | 10 | `10.10.10.0/24` | `10.10.10.1` |
| Serveurs | 20 | `10.10.20.0/24` | `10.10.20.1` |
| RH | 30 | `10.10.30.0/24` | `10.10.30.1` |
| Compta | 40 | `10.10.40.0/24` | `10.10.40.1` |
| Tech | 50 | `10.10.50.0/24` | `10.10.50.1` |
| Invités | 60 | `10.10.60.0/24` | `10.10.60.1` |
| Sauvegarde | 70 | `10.10.70.0/24` | `10.10.70.1` |

Convention : serveurs en IP fixe de `.10` à `.50` ; postes clients en DHCP de `.100` à `.200` (DHCP d'OPNsense).
Le même plan sert à toutes les équipes : leurs réseaux internes sont isolés les uns des autres.

Dans Proxmox, une VM d'une zone est branchée au bridge `<équipe>l` avec le **VLAN Tag** de sa zone
(Hardware → Network Device → VLAN Tag). Exemple : poste RH → `eq01l`, VLAN Tag `30`.

## 4. Installer OPNsense

1. **Create VM** : pool `eq01`, ISO OPNsense, OS type `Other`, 2 vCPU, 2 Go, disque 20 Go, modèle réseau **VirtIO**.
2. **Deux cartes réseau** : `net0` = `eq01w` (WAN), `net1` = `eq01l` (LAN). Ajouter la 2e : Hardware → Add → Network Device.
3. Démarrer, ouvrir la console. Se connecter avec `installer` / `opnsense`, suivre l'installation sur le disque, puis redémarrer sans l'ISO.
4. Connexion : `root` / `opnsense` (à changer tout de suite).
5. **Assigner les interfaces** : WAN = `vtnet0`, LAN = `vtnet1`.
6. **Option 2 (Set interface IP address)** :
   - WAN : IPv4 fixe `172.16.N.2/24`, passerelle `172.16.N.1`.
   - LAN : une IP temporaire, par exemple `10.10.10.1/24`.
7. **DNS** : `1.1.1.1`.
8. Interface web : depuis un poste client branché sur le LAN (`eq01l`, VLAN 10), ouvrir `https://10.10.10.1`.
9. Dans l'interface :
   - *Interfaces → WAN* : décocher **Block private networks** (le WAN est dans un réseau privé).
   - *Interfaces → Settings* : désactiver le **hardware checksum offload** (problèmes classiques avec VirtIO).
   - *Interfaces → Other Types → VLAN* : créer les VLAN 10 à 70 sur l'interface LAN, assigner chacun, donner les IP du tableau.
   - *Services → DHCPv4* : une plage `.100` à `.200` par VLAN.
   - *Firewall → Rules* : règles par zone **conformes à ta matrice de flux** (jamais « tout autoriser » entre zones).

**Test :** depuis un poste client, `ping 10.10.10.1` (passerelle), puis `ping 1.1.1.1` (Internet), puis `ping google.com` (DNS).

## 5. Ordre de construction

1. OPNsense (WAN + LAN) et ses VLAN.
2. Serveur Debian de l'annuaire, en VLAN 20, IP fixe.
3. Poste client en VLAN 10 pour administrer.
4. Les autres serveurs et postes, un par un, en suivant le sujet.

Une VM qui a besoin d'Internet (installation Debian netinst) doit être derrière OPNsense : bridge `<équipe>l` avec VLAN Tag, passerelle `10.10.X.1`, DNS `10.10.X.1` ou `1.1.1.1`.

## 6. En cas de problème

| Symptôme | À vérifier |
|---|---|
| 403 à la création | Pool choisi ? Bridge `<équipe>w`/`l` (pas `vmbr0`) ? |
| Pas d'Internet sur OPNsense | IP WAN `172.16.N.2/24`, passerelle `172.16.N.1`, « Block private networks » décoché |
| Une VM ne joint pas la passerelle | VLAN Tag correct dans Proxmox ? VLAN créé dans OPNsense ? |
| Pas de DHCP | Service DHCPv4 activé sur le VLAN ? VM sur le bon VLAN Tag ? |

Charte : tous les tests (scans, captures, simulation de chiffrement) se font **uniquement dans votre lab**, jamais sur le réseau de l'école ou d'un tiers. Aucun mot de passe ni clé privée dans les rendus.