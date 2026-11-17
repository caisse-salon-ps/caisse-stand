/* Service worker de la caisse : l'appli s'ouvre même sans réseau.
   Stratégie « stale-while-revalidate » : on sert tout de suite la copie en cache,
   puis on la met à jour en arrière-plan. Les appels à Supabase (autre domaine) ne
   passent jamais par ici. Changez VERSION pour forcer un nettoyage des anciens caches. */
var VERSION = 'caisse-1.2.2';
var SHELL = ['./', 'index.html', 'config.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png'];

self.addEventListener('install', function(e){
  e.waitUntil(
    caches.open(VERSION)
      .then(function(c){ return Promise.all(SHELL.map(function(u){ return c.add(new Request(u, {cache:'reload'})).catch(function(){}); })); })
      .then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function(e){
  e.waitUntil(
    caches.keys()
      .then(function(keys){ return Promise.all(keys.filter(function(k){ return k !== VERSION; }).map(function(k){ return caches.delete(k); })); })
      .then(function(){ return self.clients.claim(); })
  );
});

/* Prévient les pages ouvertes. Deux envois : le premier peut partir avant que la page qui vient de se charger existe encore ; le second la rattrape. */
function notify(){
  var once = function(){ return self.clients.matchAll({type:'window', includeUncontrolled:true}).then(function(cs){ cs.forEach(function(c){ c.postMessage({type:'updated'}); }); }); };
  return once().then(function(){ return new Promise(function(r){ setTimeout(r, 1500); }); }).then(once);
}
self.addEventListener('fetch', function(e){
  var req = e.request, url = new URL(req.url);
  if(req.method !== 'GET' || url.origin !== self.location.origin) return;
  e.respondWith(
    caches.open(VERSION).then(function(cache){
      return cache.match(req, {ignoreSearch:true}).then(function(hit){
        /* copie de la version en cache, prise AVANT de la donner à la page (sinon son contenu n'est plus lisible) */
        var old = hit ? hit.clone() : null;
        var isText = /\.(html|js)$|\/$/.test(url.pathname);
        var net = fetch(req).then(function(res){
          if(!(res && res.ok && res.type === 'basic')) return res;
          var same = old && isText
            ? Promise.all([old.text(), res.clone().text()]).then(function(t){ return t[0] === t[1]; }, function(){ return true; })
            : Promise.resolve(true);
          return same.then(function(same){
            return cache.put(req, res.clone()).then(function(){ return same ? null : notify(); });
          }).then(function(){ return res; }, function(){ return res; });
        }).catch(function(){ return null; });
        if(hit){ e.waitUntil(net); return hit; }
        return net.then(function(res){
          if(res) return res;
          if(req.mode === 'navigate') return cache.match('index.html');
          return new Response('', {status:504, statusText:'Hors ligne'});
        });
      });
    })
  );
});
