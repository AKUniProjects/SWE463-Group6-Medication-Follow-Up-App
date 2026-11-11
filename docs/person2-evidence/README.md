# Actual Person 2 evidence

These JPEGs are unedited captures from the running Flutter web app or the running backend verification target, using fictional fixtures and local Firebase emulators. The phone-sized captures use a 390×844 browser viewport; they are **web evidence, not Android-device evidence**. The Firebase emulator warning is intentionally visible.

| File | Observed state |
|---|---|
| [01-empty-medications.jpg](01-empty-medications.jpg) | Final empty list after confirmed soft deletion |
| [02-validation.jpg](02-validation.jpg) | Actual invalid Add form with required-field errors |
| [03-medication-added.jpg](03-medication-added.jpg) | Saved medication after Add and Edit, with shared remaining stock |
| [04-today-shared-state.jpg](04-today-shared-state.jpg) | Today reads the same persisted medication and zero stock |
| [05-edit-prefill.jpg](05-edit-prefill.jpg) | Shared Edit form prefilled from the saved record |
| [06-refill-low-stock.jpg](06-refill-low-stock.jpg) | Six tablets, two daily times, one tablet per dose: 3.0 days; threshold 7 means Low supply |
| [07-update-supply-dialog.jpg](07-update-supply-dialog.jpg) | Actual Update Supply dialog |
| [08-zero-supply.jpg](08-zero-supply.jpg) | Persisted zero supply and Out of stock |
| [09-persisted-after-reload.jpg](09-persisted-after-reload.jpg) | Medication and zero supply survived browser reload with the existing emulator/session |
| [10-delete-confirmation.jpg](10-delete-confirmation.jpg) | Full-screen Keep/Confirm delete decision |
| [11-backend-checks-passed.jpg](11-backend-checks-passed.jpg) | Four assertion-based checks passed using the real FlutterFire adapter |
| [12-after-delete.jpg](12-after-delete.jpg) | Confirm completed and medication disappeared from active lists |

Captures 02 and 09 were taken earlier in the verification flow, before the final web-emulator banner spacing adjustment. The final list/editor/refill/delete captures show the corrected layout. No screenshot claims notification delivery.

Text files contain actual baseline/final command output; trailing terminal padding was trimmed from the two analyzer headings. See [the verification record](../PERSON2_VERIFICATION.md) for exact totals, reproduction, resolved failures and checks that could not run.
