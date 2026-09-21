# Dynamic Content Restriction

Salesforce Apex package that blocks file uploads and notes by **extension/type + object**.

Example shipped rules:
- **`.pdf` files cannot be uploaded to Account**
- **Notes (classic + Enhanced) cannot be created on Account**

## How it works

1. Admins define rules in Custom Metadata type `File_Extension_Restriction__mdt`.
2. Triggers run on:
   - `ContentVersion` (before insert) — file or Enhanced Note uploaded directly to a record
   - `ContentDocumentLink` (before insert) — existing file/note linked to a record
   - `Note` (before insert) — classic Notes attached to a record
3. `FileExtensionRestrictionService` checks the target object and file/note type, then blocks the DML with a clear error.

User / Group links are ignored so profile photos and private library behavior are not affected.

## Configure a restriction

Setup → Custom Metadata Types → **File Extension Restriction** → Manage Records → New

| Field | Example | Notes |
| --- | --- | --- |
| Label | Account PDF Block | Any label |
| File Extension Restriction Name | Account_PDF | Unique developer name |
| Object API Name | `Account` | Works for any object API name |
| Restricted Extensions | `pdf` | Comma-separated: `pdf,exe,.js` — also supports note tokens below |
| Is Active | `true` | Uncheck to disable without deleting |
| Error Message | `Files with extension .{extension} cannot be uploaded to {object} records.` | Optional; supports `{extension}` and `{object}` |

### Note tokens

| Token | Blocks |
| --- | --- |
| `snote` | Enhanced Notes (`ContentNote` / FileType `SNOTE`) |
| `note` | Classic Notes (`Note` object) |

### More examples

- Block `.exe` and `.js` on Case: Object = `Case`, Extensions = `exe,js`
- Block `.xlsx` on Opportunity: Object = `Opportunity`, Extensions = `xlsx`
- Block all notes on Account: Object = `Account`, Extensions = `note,snote`
- Multiple rules for the same object are merged.

Sample metadata included:
- `File_Extension_Restriction.Account_PDF`
- `File_Extension_Restriction.Account_Notes`

## Deploy

```bash
sf org login web --alias myorg
sf project deploy start --source-dir force-app --target-org myorg
sf apex run test --class-names FileExtensionRestrictionServiceTest --result-format human --code-coverage --target-org myorg
```

Or with Metadata API / VS Code Salesforce Extension Pack: deploy the `force-app` folder.

## Manual test in the org

1. Deploy the package (includes Account PDF and Account Notes rules).
2. Open any Account → Related → Files → Upload a `.pdf` → expect an error.
3. Upload a `.txt` on the same Account → should succeed.
4. Upload a `.pdf` on a Contact → should succeed (rule is Account-only).
5. Add a classic Note or Enhanced Note on Account → expect an error.
6. Add a Note on Contact → should succeed.

## Project structure

```
force-app/main/default/
  classes/
    FileExtensionRestrictionService.cls
    FileExtensionRestrictionServiceTest.cls
  triggers/
    ContentDocumentLinkTrigger.trigger
    ContentVersionTrigger.trigger
    NoteTrigger.trigger
  objects/File_Extension_Restriction__mdt/
  customMetadata/
    File_Extension_Restriction.Account_PDF.md-meta.xml
    File_Extension_Restriction.Account_Notes.md-meta.xml
```
