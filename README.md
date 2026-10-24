# Creator Tycoon Online

Jeu de simulation de créateur vidéo en français, avec **classement multijoueur réel** via Supabase. Le jeu n'invente pas de concurrents : les rangs affichés viennent des comptes réellement créés dans le même projet Supabase.

## Contenu

- `index.html` : interface complète (HTML/CSS/JS), à ouvrir localement ou héberger sur un site statique.
- `setup.sql` : tables, politiques de sécurité, fonctions de jeu côté base de données et configuration Realtime.

## Mise en route

1. Crée un projet sur [Supabase](https://supabase.com/dashboard).
2. Dans **SQL Editor**, ouvre une nouvelle requête, colle tout le contenu de `setup.sql`, puis exécute-le.
3. Dans **Authentication → Sign In / Providers**, active **Anonymous sign-ins**. Le jeu utilise une identité anonyme persistante par navigateur pour créer un profil de jeu ; une authentification e-mail n'est pas nécessaire pour cette première version.
4. Dans **Project Settings → API** (ou Connect selon l'interface), copie la **Project URL** et la **publishable key** (ou l'ancienne clé publique `anon`). Ne prends pas la clé secrète/service_role.
5. Ouvre `index.html`, clique sur **Connexion serveur**, colle ces deux valeurs et connecte-toi.
6. Choisis un pseudo. Pour partager le classement, les autres joueurs doivent utiliser la même URL et la même clé publique, par exemple sur le même site hébergé.

## Où héberger le jeu ?

Tu peux tester en ouvrant `index.html` dans un navigateur. Pour inviter des amis facilement, héberge le fichier sur GitHub Pages, Netlify ou un autre hébergeur statique en HTTPS. La configuration Supabase est enregistrée dans le stockage local du navigateur.

## Fonctionnalités

- Profil persistant, abonnés, trésorerie, vues et réputation.
- Création de vidéos avec thématique, format, qualité et budget de promotion.
- Calcul des vues, nouveaux abonnés, coûts et revenus côté base de données.
- Tendances de marché et formats populaires partagés, qui tournent au fil des actions des joueurs.
- Classement partagé trié par abonnés et mis à jour en temps réel (avec actualisation périodique de secours).
- Bad buzz contre un joueur réel dans le classement, à partir de choix prédéfinis, avec succès possible, retour de flamme et délai de récupération.
- Fil d'activité commun.

## Limites de cette version

C'est un prototype multijoueur fonctionnel, pas une plateforme de production anti-triche complète. Les résultats sont partagés réellement sur Supabase, mais un jeu public à grande échelle demanderait notamment des contrôles de spam, de modération, des migrations versionnées, des tests automatisés et une stratégie contre les comptes multiples. Les identités anonymes restent liées au navigateur ; vider ses données locales peut faire perdre l'accès à ce profil.
