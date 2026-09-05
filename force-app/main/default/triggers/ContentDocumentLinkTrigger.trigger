trigger ContentDocumentLinkTrigger on ContentDocumentLink (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FileExtensionRestrictionService.validateDocumentLinks(Trigger.new);
    }
}
