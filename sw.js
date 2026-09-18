// Produtos Gilçana Gerente V1.8 — desativa o cache PWA durante o desenvolvimento.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  const keys=await caches.keys();
  await Promise.all(keys.filter(k=>k.startsWith('gilcana-gerente')).map(k=>caches.delete(k)));
  await self.registration.unregister();
  const clientsList=await self.clients.matchAll({type:'window'});
  for(const client of clientsList) client.navigate(client.url);
})()));
