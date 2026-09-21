trigger NoteTrigger on Note (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FileExtensionRestrictionService.validateNotes(Trigger.new);
    }
}
