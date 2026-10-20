# nexora-usb — Nexora 1.1
Transport CTAPHID, périphérique USB, serveur USB/IP et branchement via client usbip-win2.

**Dépendance locale** : cloner `nexora-fido` à côté de `nexora-usb`.

```powershell
dotnet test .\Nexora.Usb.sln -c Release
```

Le pilote signé USB/IP n'est pas redistribué dans ce dépôt. Pas de désactivation des protections Windows.
