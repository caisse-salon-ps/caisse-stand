# Caisse du stand — Province Sud (version hébergée)

Application de caisse et de stock pour le stand du salon de l'agriculture : calcul du prix des ventes en direct (euros avec décimales, ventes à l'unité), stock partagé en temps réel entre plusieurs smartphones et tablettes, fonctionnement même sans réseau.

**Ce qu'il faut mettre en place** : une page web hébergée sur GitHub Pages + une base Supabase + une petite tâche automatique quotidienne. Compter 45 minutes à 1 heure la première fois.

| Fichier | Rôle |
|---|---|
| `index.html` | L'application (une seule page) |
| `config.js` | **Les 2 valeurs à remplir** (adresse et clé publique Supabase) |
| `sw.js`, `manifest.webmanifest`, `icon-*.png` | Installation sur l'écran d'accueil + ouverture sans réseau |
| `supabase/schema.sql` | Création des tables, des droits d'accès, des sauvegardes (à coller dans Supabase) |
| `.github/workflows/keep-alive.yml` | Tâche quotidienne : empêche la mise en pause de Supabase et fait une sauvegarde |
| `.nojekyll` | Fichier technique pour GitHub Pages (ne pas supprimer) |

> Tant que `config.js` n'est pas rempli, l'application s'ouvre en **mode démo** (données stockées sur l'appareil seulement, bandeau orange). Pratique pour la montrer, mais rien n'est partagé.

---

## Étape 1 — GitHub (hébergement de la page)

1. Créez une **organisation GitHub gratuite** (menu en haut à droite → *Your organizations* → *New organization* → plan *Free*). Elle appartient à la Province plutôt qu'à une personne.
2. Dans cette organisation : *New repository*, nom `caisse-stand`, visibilité **Public** (GitHub Pages gratuit l'exige). Le dépôt ne contiendra ni donnée ni mot de passe : seulement le code.
3. Téléversez le contenu de ce dossier (*Add file* → *Upload files*, puis glissez les fichiers **et** le dossier `supabase`). Le dossier caché `.github` passe parfois mal par le navigateur : si `.github/workflows/keep-alive.yml` n'apparaît pas dans le dépôt, créez-le à la main (*Add file* → *Create new file*, tapez le nom `.github/workflows/keep-alive.yml`, collez le contenu).
4. *Settings* → *Pages* → *Build and deployment* : source **Deploy from a branch**, branche `main`, dossier `/ (root)` → *Save*.
5. Au bout d'une minute, l'adresse de l'application s'affiche : `https://<organisation>.github.io/caisse-stand/`. Notez-la.

## Étape 2 — Supabase (la base partagée)

1. Sur supabase.com : *New project*. Choisissez la région la plus proche (Oceania / Sydney), notez le mot de passe de la base.
2. *SQL Editor* → *New query* → collez tout `supabase/schema.sql` → *Run*. Vous devez voir « Success ». (Le script peut être relancé sans danger.)
3. **Verrouillez les inscriptions** : *Authentication* → *Sign In / Providers* → désactivez **Allow new users to sign up**. Sans cela, n'importe qui connaissant l'adresse de l'application pourrait se créer un compte et lire les ventes.
4. Créez les comptes : *Authentication* → *Users* → *Add user* → *Create new user*, avec **Auto Confirm User** coché. Prévoyez un compte gestionnaire et un compte par appareil ou par personne (les adresses peuvent être fictives, par exemple `caisse1@stand-ps.nc` : aucun courriel n'est envoyé).
5. Donnez le rôle **gestionnaire** à votre compte : *SQL Editor* → *New query* :
   ```sql
   update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"manager"}'::jsonb
   where email = 'votre-adresse@exemple.nc';
   ```
   Les autres comptes sont des **vendeurs** (ils vendent, ajustent le stock, annulent une vente ; ils ne modifient ni le catalogue ni les prix). Après ce changement, déconnectez-vous puis reconnectez-vous pour que le rôle soit pris en compte.
6. Récupérez deux valeurs : l'**adresse du projet** (*Project Settings* → *Data API*, de la forme `https://xxxx.supabase.co`) et la clé **publishable** (*Project Settings* → *API Keys*, commence par `sb_publishable_`). Le bouton *Connect* en haut du tableau de bord les affiche aussi. **N'utilisez jamais la clé « secret » ou « service_role ».**

## Étape 3 — Renseigner `config.js`

Dans GitHub, ouvrez `config.js` → icône crayon → remplacez `https://VOTRE-PROJET.supabase.co` et `VOTRE-CLE-PUBLISHABLE` par vos deux valeurs → *Commit changes*. Une minute plus tard, l'adresse de l'application affiche l'écran de connexion (plus le bandeau démo).

## Étape 4 — La tâche quotidienne (anti-pause + sauvegarde)

1. Rien à saisir : le fichier `.github/workflows/keep-alive.yml` contient l'adresse du projet et la clé publishable (publiques, déjà présentes dans `config.js`). Si vous changez de projet Supabase, modifiez ces deux valeurs dans ce fichier (ou créez les secrets `SUPABASE_URL` et `SUPABASE_KEY` dans *Settings* → *Secrets and variables* → *Actions* : ils ont priorité).
2. Onglet *Actions* → *Maintenance quotidienne (anti-pause + sauvegarde)* → *Run workflow*. L'exécution doit passer au vert ; ouvrez-la : la ligne « Réponse » doit contenir `"ok": true`.
3. Ensuite, elle tourne seule chaque jour. Elle écrit et lit dans la base (ce qui évite la mise en pause d'un projet gratuit après 7 jours sans activité), crée la sauvegarde du jour (30 jours conservés) et empêche GitHub de désactiver la tâche après 60 jours sans activité. Si une exécution échoue, elle est rouge dans l'onglet *Actions* et GitHub vous écrit : **ne pas ignorer**.

## Étape 5 — Installer sur chaque appareil

Ouvrez l'adresse de l'application **avec Internet**, connectez-vous, donnez un nom à l'appareil (ex. « Caisse 1 »). Puis installez-la :

- **iPhone / iPad (Safari)** : bouton Partager → *Sur l'écran d'accueil*.
- **Android (Chrome)** : menu ⋮ → *Installer l'application* (ou *Ajouter à l'écran d'accueil*).
- **Ordinateur (Chrome / Edge)** : icône d'installation dans la barre d'adresse.

Faites-le au moins une semaine avant le salon, et ouvrez l'application une fois par jour d'ici là : Safari peut effacer les données d'un site non utilisé pendant plus de 7 jours. Une fois installée et ouverte une première fois avec du réseau, l'application **s'ouvre sans Internet**, avec le dernier catalogue connu.

## Étape 6 — Catalogue (compte gestionnaire)

Onglet **Gestion** → *Importer (CSV)* : collez vos lignes depuis Excel, au format `nom ; catégorie ; prix ; stock ; seuil d'alerte` (prix avec virgule, ex. `22,00`). Le catalogue d'exemple (20 produits fictifs) sert à s'entraîner ; *Importer → Remplacer le catalogue* le masque. Chaque produit se modifie ensuite individuellement (prix, stock de départ, seuil, visible ou non).

## Étape 7 — Répétition générale (à ne pas sauter, 20 minutes)

1. Deux ou trois appareils connectés, tous « Synchronisé ».
2. Vendre sur l'un : le stock baisse sur les autres en quelques secondes.
3. Mettre un appareil en **mode avion**, vendre : la pastille indique « Hors ligne · 1 en attente » ; couper le mode avion : la vente part seule.
4. Fermer l'application et la rouvrir en mode avion : elle s'ouvre et affiche le catalogue.
5. Annuler une vente ; exporter le CSV des ventes (onglet *Ventes*) et l'ouvrir dans Excel.
6. Avant l'ouverture : **Gestion → Remettre à zéro** (les ventes et le stock repartent du stock de départ du catalogue ; les anciennes données restent archivées dans la base mais ne sont plus comptées).

## Jour J

- Matin : sur chaque appareil, ouvrir l'application, vérifier « Synchronisé », charger les batteries. Prévoir un **second accès réseau** (partage de connexion d'un téléphone) en plus du Wi-Fi du salon.
- Pastilles : **Synchronisé** (tout est parti) · **N en attente** (en cours d'envoi) · **Hors ligne** (les ventes sont gardées sur l'appareil et partent au retour du réseau) · **Reconnexion requise** (se reconnecter ; rien n'est perdu).
- Le stock se corrige dans l'onglet **Stock** → *Ajuster* (réappro, casse, offert, inventaire).
- Si deux caisses vendent le dernier article en même temps, le stock passe à −1 en rouge : l'écart est signalé, pas masqué.
- Soir : *Gestion* → *Télécharger une sauvegarde* (JSON) et *Ventes* → export CSV, à ranger hors de l'appareil.
- Plan B (panne générale) : carnet papier et calculatrice ; les ventes seront saisies après.

## Après le salon

- Export CSV des ventes (onglet *Ventes*) ou, dans Supabase, *Table Editor* → vue `v_ventes_lignes` → *Export CSV* (une ligne par article vendu, colonne `epoque_courante` pour ignorer les ventes d'avant la remise à zéro).
- Supprimer ou désactiver les comptes (*Authentication* → *Users*), changer les mots de passe si les appareils sont prêtés.
- Décider du sort des données (conservation, destruction) avec la direction et la régie, puis mettre le projet en pause ou le supprimer.

## Sauvegardes et restauration

- Chaque jour, `maintenance()` enregistre un instantané complet dans la table `snapshots` (30 jours). Le plan gratuit de Supabase ne fournit pas de sauvegarde automatique : cet instantané la remplace, mais il reste dans le même projet, d'où le téléchargement du soir.
- Restaurer une journée (SQL Editor) : `select public.restore_snapshot('2026-02-26');` — remet les lignes à leur état de ce jour-là sans effacer celles créées depuis.

## En cas de problème

| Constat | Piste |
|---|---|
| Bandeau « Mode démo » | `config.js` pas rempli, ou page en cache : attendre une minute, recharger deux fois |
| « Identifiants incorrects » | Mot de passe erroné, ou compte créé sans *Auto Confirm User* |
| Pas d'onglet « Gestion » (seulement « Compte ») | Le compte n'a pas le rôle gestionnaire (étape 2.5), ou reconnexion à faire |
| « Hors ligne » alors que le Wi-Fi est connecté | Wi-Fi sans accès Internet ; sinon projet Supabase en pause : tableau de bord → *Restore project* |
| « Opérations refusées » dans la fenêtre Synchronisation | Une écriture a été rejetée (droits) ; copier le détail et le transmettre |
| « Mise à jour disponible » | Une nouvelle version est prête : recharger quand aucune vente n'est en cours |
| Tâche GitHub en rouge | Ouvrir l'exécution : adresse ou clé erronée dans `keep-alive.yml` (étape 4), ou projet supprimé |

## Sécurité

- La clé *publishable* est publique par conception. La protection repose sur la connexion obligatoire et sur les droits de la base : sans compte, rien n'est lisible ni modifiable ; un vendeur ne peut ni changer un prix ni modifier ou supprimer une vente (seulement l'annuler / la rétablir).
- Aucune donnée personnelle de client n'est enregistrée (ni nom, ni numéro de carte).
- Les données sont hébergées chez Supabase, hors de Nouvelle-Calédonie (région choisie à l'étape 2) : à faire valider par la DSI.

## Points à valider avec les services de la Province

- **Encaissement** : l'application calcule et enregistre les ventes ; ce n'est ni un logiciel de caisse certifié ni un terminal de paiement. Selon le statut de l'encaissement du stand (régie de recettes, TVA), un logiciel de caisse conforme ou une tenue spécifique des justificatifs peut être exigé : à confirmer avec le régisseur et la direction des finances avant le salon.
- **Propriété des comptes** (GitHub, Supabase) et conservation des données après l'événement.

## Pour aller plus loin

- Supabase **Pro** (environ 25 $ par mois) supprime tout risque de mise en pause et ajoute des sauvegardes quotidiennes officielles : à envisager si le dispositif doit durer.
- Pour modifier l'application, remplacez les fichiers dans GitHub : après environ une minute, les appareils affichent « Mise à jour disponible ».
