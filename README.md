# uDrive dual build hotfix

This patch restores two live vehicle-location contracts that were accidentally removed by the latest Driver Home overlay:

- Flutter `BookingRepository.getPackageVehicleLocation(...)`
- API `PackageVehicleLocationDto`

Apply these files over the latest source, then redeploy API first and Flutter web second.
