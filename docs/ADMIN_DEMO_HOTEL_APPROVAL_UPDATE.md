# UDrive Admin Data and Hotel Approval Update

## Admin portal

### Data Management
Open **Control Centre > Data management**.

- **Add / refresh demo data** adds or refreshes Kashmir destinations, tour packages, verified demo drivers, cars, coasters, bikes, rickshaws, approved hotels, hotel rooms and one pending hotel.
- **Delete all old data** removes operational/customer data after the administrator types `DELETE ALL DATA` and confirms the warning.
- Admin and SuperAdmin accounts, their active login records, and system settings are preserved so the portal remains accessible.
- Both Admin and SuperAdmin roles can run the reset.

### Hotels & Approvals
Open **Tourism > Hotels & approvals**.

- View all pending, approved and rejected hotel submissions.
- Search by hotel, city, owner or phone.
- Approve a hotel to publish it automatically in the customer app.
- Reject a hotel with a mandatory correction reason.
- Hide or republish an approved hotel without deleting it.

## Customer app

Open **Hotels & Stays**, then use either:

- the **Add hotel** icon in the app bar, or
- the **Own a hotel or guest house?** submission card.

The customer can submit hotel name, full address, city, district, phone, description, image URL, amenities, map coordinates and transport availability. New submissions remain pending and hidden until approved by an administrator.

## Public hotel visibility rule

The public hotel API returns only hotels where:

- `approval_status = 'Approved'`
- `is_active = true`

Approved hotels are visible even before room types are added. Booking becomes available after the hotel owner adds room types in Hotel Mode.

## Demo hotel catalogue

The demo seed contains:

- Neelum Riverside Lodge — approved
- Muzaffarabad Grand Stay — approved
- Rawalakot Pine View Hotel — approved
- Sharda Valley Guest House — pending approval test record
- Five room types across the demo properties

The demo operation is idempotent and can be run repeatedly without duplicating the fixed demo records.
