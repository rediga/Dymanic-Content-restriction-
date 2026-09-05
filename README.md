# Dynamic Content Restriction

Salesforce Apex package that blocks file uploads by **extension + object**.

Example shipped rule: **`.pdf` files cannot be uploaded to Account**.

## How it works

1. Admins define rules in Custom Metadata type `File_Extension_Restriction__mdt`.
2. Triggers run on:
   - `ContentVersion` (before insert) — file uploaded directly to a record
   - `ContentDocumentLink` (before insert) — existing file linked to a record
3. `FileExtensionRestrictionService` checks the target object and file extension, then blocks the DML with a clear error.

User / Group links are ignored so profile photos and private library behavior are not affected.

## Configure a restriction

Setup → Custom Metadata Types → **File Extension Restriction** → Manage Records → New

| Field | Example | Notes |
| --- | --- | --- |
| Label | Account PDF Block | Any label |
| File Extension Restriction Name | Account_PDF | Unique developer name |
| Object API Name | `Account` | Works for any object API name |
| Restricted Extensions | `pdf` | Comma-separated: `pdf,exe,.js` |
| Is Active | `true` | Uncheck to disable without deleting |
| Error Message | `Files with extension .{extension} cannot be uploaded to {object} records.` | Optional; supports `{extension}` and `{object}` |

### More examples

- Block `.exe` and `.js` on Case: Object = `Case`, Extensions = `exe,js`
- Block `.xlsx` on Opportunity: Object = `Opportunity`, Extensions = `xlsx`
- Multiple rules for the same object are merged.

Sample metadata included: `File_Extension_Restriction.Account_PDF`.

## Deploy

```bash
sf org login web --alias myorg
sf project deploy start --source-dir force-app --target-org myorg
sf apex run test --class-names FileExtensionRestrictionServiceTest --result-format human --code-coverage --target-org myorg
```

Or with Metadata API / VS Code Salesforce Extension Pack: deploy the `force-app` folder.

## Manual test in the org

1. Deploy the package (includes Account PDF rule).
2. Open any Account → Related → Files → Upload a `.pdf` → expect an error.
3. Upload a `.txt` on the same Account → should succeed.
4. Upload a `.pdf` on a Contact → should succeed (rule is Account-only).

## Project structure

```
force-app/main/default/
  classes/
    FileExtensionRestrictionService.cls
    FileExtensionRestrictionServiceTest.cls
  triggers/
    ContentDocumentLinkTrigger.trigger
    ContentVersionTrigger.trigger
  objects/File_Extension_Restriction__mdt/
  customMetadata/File_Extension_Restriction.Account_PDF.md-meta.xml
```
