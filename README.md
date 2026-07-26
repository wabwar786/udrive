# BookingService complete driver-scope hotfix

Replace exactly:
`udrive_api/Services/BookingService.cs`

This package is based on the latest Driver Home premium BookingService and corrects the out-of-scope `driver.DriverProfileId` reference in the selected-offer transaction to the in-scope `driverProfileId` variable.
