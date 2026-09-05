trigger ContentVersionTrigger on ContentVersion (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FileExtensionRestrictionService.validateContentVersions(Trigger.new);
    }
}
