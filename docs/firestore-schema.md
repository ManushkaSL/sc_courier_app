# Firestore schema for the courier database

This document converts the provided SQL schema into Cloud Firestore collections. Firestore has no joins or foreign-key constraints, so SQL foreign keys are represented as string ID fields that store the referenced document ID. Use Firebase Authentication UIDs for user-owned documents where possible.

## Top-level collections

### `customers/{customerId}`
Source table: `Customer`

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | From `cust_name`. |
| `email` | string | From `cust_email`; keep unique with an app-level check or Auth email. |
| `address` | string | From `cust_address`. |
| `phoneNumber` | string | Required; from `cust_phoneNo`. |
| `type` | string | Required; from `cust_type`. |
| `createdAt` | timestamp | Use `serverTimestamp()` on create. |

Do not store `cust_password` in Firestore. Use Firebase Authentication for passwords.

### `companies/{companyId}`
Source table: `Company`

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Required; from `comp_name`. |
| `address` | string | Required; from `comp_address`. |
| `phoneNumber` | string | Required; from `comp_phoneNo`. |

### `departments/{departmentId}`
Source table: `Department`

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Required; from `dep_name`. |
| `companyId` | string | Document ID from `companies`. |

### `reviews/{reviewId}`
Source table: `Reviews`

| Field | Type | Notes |
| --- | --- | --- |
| `comment` | string | From `review_com`. |
| `customerId` | string | Document ID from `customers`. |
| `createdAt` | timestamp | Recommended for ordering. |

### `branches/{branchId}`
Source table: `Branch`

| Field | Type | Notes |
| --- | --- | --- |
| `location` | string | From `branch_location`. |

### `staff/{staffId}`
Source table: `Staff`

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Required; from `staff_name`. |
| `phone` | string | Required; from `staff_phone`. |
| `branchId` | string | Document ID from `branches`. |
| `role` | string | From `staff_role`. |
| `active` | boolean | From `staff_active_status`. |
| `email` | string | Unique with an app-level check or Auth email. |

Do not store `staff_password` in Firestore. Use Firebase Authentication and custom claims for staff/admin roles.

### `invoices/{invoiceId}`
Source table: `Invoice`

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | From `invoice_type`. |
| `customerId` | string | Document ID from `customers`. |
| `riderId` | string | Document ID from `staff` or `riders`, depending on your final rider model. |
| `issueDate` | timestamp | From `issue_date`. |
| `billingPeriodStart` | timestamp | From `billing_period_start`. |
| `billingPeriodEnd` | timestamp | From `billing_period_end`. |
| `totalAmount` | number | From `total_amount`. |
| `paymentStatus` | string | From `payment_status`. |

### `payments/{paymentId}`
Source table: `Payment`

| Field | Type | Notes |
| --- | --- | --- |
| `invoiceId` | string | Document ID from `invoices`. |
| `paymentDate` | timestamp | From `payment_date`. |
| `paymentMethod` | string | From `payment_method`. |
| `amount` | number | From `amount`. |
| `status` | string | From `status`. |
| `transactionId` | string | From `transaction_id`. |

### `atrRequests/{atrId}`
Source table: `ATR`

| Field | Type | Notes |
| --- | --- | --- |
| `departmentId` | string | Document ID from `departments`. |
| `atrNumber` | string | Unique with an app-level check. |
| `requiredDate` | timestamp | From `required_date`. |
| `requiredTime` | string | Store as `HH:mm` unless exact date-time is preferred. |
| `vehicleType` | string | From `vehicle_type`. |
| `purposeOfTravel` | string | From `purpose_of_travel`. |
| `principalPassengerName` | string | From `principal_passenger_name`. |
| `principalPassengerDesignation` | string | From `principal_passenger_designation`. |
| `estimatedDistance` | number | From `estimated_distance`. |
| `estimatedCost` | number | From `estimated_cost`. |
| `actualDistance` | number | From `actual_distance`. |
| `actualCost` | number | From `actual_cost`. |
| `status` | string | From `status`. |
| `approvedBy` | string | Document ID from `staff`. |
| `approvalDate` | timestamp | From `approval_date`. |

### `trips/{tripId}`
Source table: `Trip`

| Field | Type | Notes |
| --- | --- | --- |
| `riderId` | string | Document ID from `staff` or `riders`. |
| `tripDate` | timestamp | From `trip_date`. |
| `status` | string | From `trip_status`. |

### `receivers/{receiverId}`
Source table: `Receiver`

Use `rec_NIC` as the document ID if it is stable and non-sensitive enough for your use case.

| Field | Type | Notes |
| --- | --- | --- |
| `nic` | string | From `rec_NIC`; duplicate field is optional if it is also the document ID. |
| `phone` | string | Required; from `rec_PHONE`. |
| `name` | string | Required; from `rec_NAME`. |
| `location` | string | Required; from `rec_LOCATION`. |

### `courierRequests/{requestId}`
Source table: `Courier_req`

| Field | Type | Notes |
| --- | --- | --- |
| `customerId` | string | Document ID from `customers`. |
| `receiverId` | string | Document ID from `receivers`. |
| `atrId` | string | Document ID from `atrRequests`. |
| `courierDate` | timestamp | From `courier_date`. |
| `courierWeight` | string | From `courier_weight`. |
| `status` | string | From `status`. |
| `createdAt` | timestamp | Use `serverTimestamp()` on create. |

### `deliveries/{deliveryId}`
Source table: `Delivery`

| Field | Type | Notes |
| --- | --- | --- |
| `tracking_code` | string | Defaults to the delivery document ID; customer-facing lookup code. |
| `parcel_id` | string | Same as `tracking_code` for parcel search compatibility. |
| `rider_id` | string | Firebase UID from `riders/{riderId}`. |
| `status` | string | From `delivery_status`. |
| `pickLocation` | string | From `pick_location`. |
| `dropLocation` | string | From `drop_location`. |
| `rider_live_location` | map | Mirrored latest rider coordinates while this delivery is active. |
| `rider_location_updated_at` | timestamp | Server timestamp for the mirrored rider location. |
| `live_tracking_enabled` | boolean | True when the delivery should expose live tracking. |
| `courierRequestId` | string | Document ID from `courierRequests`. |
| `tripId` | string | Document ID from `trips`. |
| `createdAt` | timestamp | Use `serverTimestamp()` on create. |

### `riderLocations/{riderId}`
Live location document written by the rider app while GPS tracking is enabled.

| Field | Type | Notes |
| --- | --- | --- |
| `rider_id` | string | Firebase UID; same as the document ID. |
| `latitude` | number | Latest GPS latitude. |
| `longitude` | number | Latest GPS longitude. |
| `accuracy` | number | Accuracy in meters. |
| `speed` | number | Speed in meters per second. |
| `heading` | number | Heading in degrees. |
| `is_online` | boolean | True while rider tracking is active, false after stop/logout. |
| `updated_at` | timestamp | Server timestamp for the last location/status write. |
| `stopped_at` | timestamp | Server timestamp set when tracking stops. |

### `notifications/{notificationId}`
Source table: `Notification`

| Field | Type | Notes |
| --- | --- | --- |
| `customerId` | string | Document ID from `customers`. |
| `deliveryId` | string | Document ID from `deliveries`. |
| `type` | string | From `notification_type`. |
| `sentDate` | timestamp | From `sent_date`. |
| `message` | string | From `notification_msg`. |

### `riders/{riderId}`
Source table: `Rider`

Use a Firebase Authentication UID as `riderId`. Store image uploads in Firebase Storage and keep file paths or download URLs in Firestore.

| Field | Type | Notes |
| --- | --- | --- |
| `nic` | string | From `NIC`; avoid using sensitive IDs as document IDs if possible. |
| `name` | string | Required; from `Name`. |
| `phoneNumber` | string | Required; from `Phone_Number`. |
| `branch` | string | From `Branch`; consider `branchId` if linked to `branches`. |
| `email` | string | Unique with Auth email. |
| `nicFrontImageUrl` | string | From `NIC_Front_Image`. |
| `nicBackImageUrl` | string | From `NIC_Back_Image`. |
| `address` | string | From `Address`. |
| `emergencyContact` | string | From `Emergency_Contact`. |
| `vehicleType` | string | From `Vehicle_Type`. |
| `vehicleNo` | string | From `Vehicle_No`. |
| `driverLicenceNo` | string | From `Driver_Licence_No`. |

Do not store `Password` in Firestore. Use Firebase Authentication.

## Recommended Auth model

- Customers: Firebase Auth users with normal user permissions.
- Staff/admin: Firebase Auth users with custom claims such as `role: "staff"` or `role: "admin"`.
- Riders: Firebase Auth users with a `role: "rider"` claim, or staff records with `staff.role = "rider"` if you want one unified staff model.

## Deploying the Firestore config

1. Create or select a Firebase project in the Firebase Console.
2. Install the Firebase CLI if needed: `npm install -g firebase-tools`.
3. Log in: `firebase login`.
4. Link the repo to your Firebase project: `firebase use --add`.
5. Deploy rules and indexes: `firebase deploy --only firestore`.
