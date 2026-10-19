# Configuração Android

Ao criar/gerar o projeto Flutter Android, confirme que `android/app/src/main/AndroidManifest.xml` inclui:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

A camada de mapa usa tiles públicos do OpenStreetMap e o traçado usa o endpoint público de demonstração do OSRM. Esses serviços podem limitar tráfego e não são recomendados como backend garantido para produção.
