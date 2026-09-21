@IsTest
private class FileExtensionRestrictionServiceTest {
    @TestSetup
    static void setupData() {
        insert new Account(Name = 'Restriction Test Account');
        insert new Contact(LastName = 'Restriction Test Contact');
    }

    @IsTest
    static void parseExtensions_normalizesDotsAndSeparators() {
        Set<String> extensions = FileExtensionRestrictionService.parseExtensions('pdf, .PDF; exe  js');
        System.assertEquals(3, extensions.size(), 'Expected three unique extensions');
        System.assert(extensions.contains('pdf'));
        System.assert(extensions.contains('exe'));
        System.assert(extensions.contains('js'));
    }

    @IsTest
    static void buildRestrictionError_blocksConfiguredExtension() {
        Map<String, FileExtensionRestrictionService.RestrictionRule> rules =
            new Map<String, FileExtensionRestrictionService.RestrictionRule>{
                'account' => new FileExtensionRestrictionService.RestrictionRule(
                    'account',
                    new Set<String>{ 'pdf' },
                    'Blocked .{extension} on {object}'
                )
            };

        String errorMessage = FileExtensionRestrictionService.buildRestrictionError(
            'Account',
            'PDF',
            rules
        );

        System.assertEquals('Blocked .pdf on Account', errorMessage);
        System.assertEquals(
            null,
            FileExtensionRestrictionService.buildRestrictionError('Account', 'docx', rules),
            'Unlisted extensions should be allowed'
        );
        System.assertEquals(
            null,
            FileExtensionRestrictionService.buildRestrictionError('Contact', 'pdf', rules),
            'Other objects should not inherit Account rules'
        );
    }

    @IsTest
    static void buildRestrictionError_blocksNoteTokens() {
        Map<String, FileExtensionRestrictionService.RestrictionRule> rules =
            new Map<String, FileExtensionRestrictionService.RestrictionRule>{
                'account' => new FileExtensionRestrictionService.RestrictionRule(
                    'account',
                    new Set<String>{ 'note', 'snote' },
                    'Notes cannot be created on {object} records.'
                )
            };

        System.assertEquals(
            'Notes cannot be created on Account records.',
            FileExtensionRestrictionService.buildRestrictionError('Account', 'note', rules)
        );
        System.assertEquals(
            'Notes cannot be created on Account records.',
            FileExtensionRestrictionService.buildRestrictionError('Account', 'snote', rules)
        );
        System.assertEquals(
            null,
            FileExtensionRestrictionService.buildRestrictionError('Contact', 'note', rules)
        );
    }

    @IsTest
    static void validateContentVersions_blocksPdfOnAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        FileExtensionRestrictionService.testRulesByObject =
            new Map<String, FileExtensionRestrictionService.RestrictionRule>{
                'account' => new FileExtensionRestrictionService.RestrictionRule(
                    'account',
                    new Set<String>{ 'pdf' },
                    'Files with extension .{extension} cannot be uploaded to {object} records.'
                )
            };

        ContentVersion blocked = new ContentVersion(
            Title = 'Blocked Account File',
            PathOnClient = 'invoice.pdf',
            VersionData = Blob.valueOf('pdf-bytes'),
            FirstPublishLocationId = account.Id
        );
        ContentVersion allowedOnContact = new ContentVersion(
            Title = 'Allowed Contact File',
            PathOnClient = 'invoice.pdf',
            VersionData = Blob.valueOf('pdf-bytes'),
            FirstPublishLocationId = contact.Id
        );
        ContentVersion allowedExtension = new ContentVersion(
            Title = 'Allowed Account Doc',
            PathOnClient = 'notes.txt',
            VersionData = Blob.valueOf('text-bytes'),
            FirstPublishLocationId = account.Id
        );

        Test.startTest();
        try {
            insert blocked;
            System.assert(false, 'PDF upload to Account should fail');
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('pdf'),
                'Expected PDF restriction error, got: ' + ex.getMessage()
            );
        }

        insert new List<ContentVersion>{ allowedOnContact, allowedExtension };
        Test.stopTest();

        System.assertEquals(
            2,
            [SELECT COUNT() FROM ContentVersion WHERE Title IN ('Allowed Contact File', 'Allowed Account Doc')],
            'Non-restricted uploads should succeed'
        );
    }

    @IsTest
    static void validateContentVersions_blocksEnhancedNotesOnAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        FileExtensionRestrictionService.testRulesByObject =
            new Map<String, FileExtensionRestrictionService.RestrictionRule>{
                'account' => new FileExtensionRestrictionService.RestrictionRule(
                    'account',
                    new Set<String>{ 'snote' },
                    'Notes cannot be created on {object} records.'
                )
            };

        ContentVersion blockedNote = new ContentVersion(
            Title = 'Blocked Account Note',
            PathOnClient = 'Blocked Account Note.snote',
            VersionData = Blob.valueOf('note-bytes'),
            FirstPublishLocationId = account.Id
        );
        ContentVersion allowedOnContact = new ContentVersion(
            Title = 'Allowed Contact Note',
            PathOnClient = 'Allowed Contact Note.snote',
            VersionData = Blob.valueOf('note-bytes'),
            FirstPublishLocationId = contact.Id
        );

        Test.startTest();
        try {
            insert blockedNote;
            System.assert(false, 'Enhanced Note on Account should fail');
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('Notes cannot be created'),
                'Expected note restriction error, got: ' + ex.getMessage()
            );
        }

        insert allowedOnContact;
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentVersion WHERE Title = 'Allowed Contact Note'],
            'Enhanced Notes on Contact should succeed'
        );
    }

    @IsTest
    static void validateDocumentLinks_blocksPdfWhenLinkedToAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        FileExtensionRestrictionService.testRulesByObject =
            new Map<String, FileExtensionRestrictionService.RestrictionRule>{
                'account' => new FileExtensionRestrictionService.RestrictionRule(
                    'account',
                    new Set<String>{ 'pdf' },
                    'Files with extension .{extension} cannot be uploaded to {object} records.'
                )
            };

        // Create a file in the library (no record publish location) then link it.
        ContentVersion version = new ContentVersion(
            Title = 'Shared PDF',
            PathOnClient = 'shared.pdf',
            VersionData = Blob.valueOf('pdf-bytes')
        );
        insert version;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;

        ContentDocumentLink accountLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = account.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        ContentDocumentLink contactLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = contact.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        try {
            insert accountLink;
            System.assert(false, 'Linking PDF to Account should fail');
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('pdf'),
                'Expected PDF restriction error, got: ' + ex.getMessage()
            );
        }

        insert contactLink;
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId = :contact.Id
            ],
            'Linking the same PDF to Contact should succeed'
        );
    }

    @IsTest
    static void validateNotes_blocksClassicNotesOnAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        FileExtensionRestrictionService.testRulesByObject =
            new Map<String, FileExtensionRestrictionService.RestrictionRule>{
                'account' => new FileExtensionRestrictionService.RestrictionRule(
                    'account',
                    new Set<String>{ 'note' },
                    'Notes cannot be created on {object} records.'
                )
            };

        Note blocked = new Note(
            Title = 'Blocked Account Note',
            Body = 'Should fail',
            ParentId = account.Id
        );
        Note allowed = new Note(
            Title = 'Allowed Contact Note',
            Body = 'Should succeed',
            ParentId = contact.Id
        );

        Test.startTest();
        try {
            insert blocked;
            System.assert(false, 'Classic Note on Account should fail');
        } catch (DmlException ex) {
            System.assert(
                ex.getMessage().contains('Notes cannot be created'),
                'Expected note restriction error, got: ' + ex.getMessage()
            );
        }

        insert allowed;
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Note WHERE Title = 'Allowed Contact Note'],
            'Classic Notes on Contact should succeed'
        );
    }

    @IsTest
    static void resolveExtension_fallsBackToFileName() {
        System.assertEquals(
            'pdf',
            FileExtensionRestrictionService.resolveExtension(null, 'Report.PDF', null)
        );
        System.assertEquals(
            'csv',
            FileExtensionRestrictionService.resolveExtension(null, null, 'export.csv')
        );
        System.assertEquals(
            'docx',
            FileExtensionRestrictionService.resolveExtension('DOCX', 'ignored.txt', 'ignored.csv')
        );
    }

    @IsTest
    static void resolveExtension_detectsEnhancedNotesFromFileType() {
        System.assertEquals(
            'snote',
            FileExtensionRestrictionService.resolveExtension(null, null, 'Meeting Notes', 'SNOTE')
        );
        System.assertEquals(
            'snote',
            FileExtensionRestrictionService.resolveExtension('snote', 'Meeting Notes.snote', null, null)
        );
    }
}
