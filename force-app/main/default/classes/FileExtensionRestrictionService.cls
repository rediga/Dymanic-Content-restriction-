/**
 * Evaluates whether a file extension is restricted for a given object.
 * Rules are stored in File_Extension_Restriction__mdt so admins can
 * block extensions per object without code changes.
 *
 * Example: Restrict .pdf uploads on Account only.
 */
public with sharing class FileExtensionRestrictionService {
    private static final String DEFAULT_ERROR =
        'Files with extension .{extension} cannot be uploaded to {object} records.';

    @TestVisible
    private static Map<String, RestrictionRule> testRulesByObject;

    public class RestrictionRule {
        public String objectApiName;
        public Set<String> extensions;
        public String errorMessage;

        public RestrictionRule(String objectApiName, Set<String> extensions, String errorMessage) {
            this.objectApiName = objectApiName;
            this.extensions = extensions == null ? new Set<String>() : extensions;
            this.errorMessage = errorMessage;
        }
    }

    /**
     * Validates ContentDocumentLink rows before insert.
     * Blocks links when the target object has a matching restricted extension.
     */
    public static void validateDocumentLinks(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }

        Map<String, RestrictionRule> rulesByObject = getRulesByObject();
        if (rulesByObject.isEmpty()) {
            return;
        }

        Set<Id> documentIds = new Set<Id>();
        List<ContentDocumentLink> candidates = new List<ContentDocumentLink>();

        for (ContentDocumentLink link : links) {
            if (link == null || link.LinkedEntityId == null || link.ContentDocumentId == null) {
                continue;
            }
            if (!isRestrictableEntity(link.LinkedEntityId)) {
                continue;
            }

            String objectApiName = link.LinkedEntityId.getSObjectType().getDescribe().getName();
            if (!rulesByObject.containsKey(normalizeObjectName(objectApiName))) {
                continue;
            }

            documentIds.add(link.ContentDocumentId);
            candidates.add(link);
        }

        if (candidates.isEmpty()) {
            return;
        }

        Map<Id, String> extensionByDocumentId = getLatestExtensionByDocumentId(documentIds);

        for (ContentDocumentLink link : candidates) {
            String objectApiName = link.LinkedEntityId.getSObjectType().getDescribe().getName();
            String extension = extensionByDocumentId.get(link.ContentDocumentId);
            String errorMessage = buildRestrictionError(objectApiName, extension, rulesByObject);
            if (String.isNotBlank(errorMessage)) {
                link.addError(errorMessage);
            }
        }
    }

    /**
     * Validates ContentVersion rows when FirstPublishLocationId points at a record.
     * Covers Files uploaded directly onto a record.
     */
    public static void validateContentVersions(List<ContentVersion> versions) {
        if (versions == null || versions.isEmpty()) {
            return;
        }

        Map<String, RestrictionRule> rulesByObject = getRulesByObject();
        if (rulesByObject.isEmpty()) {
            return;
        }

        for (ContentVersion version : versions) {
            if (version == null || version.FirstPublishLocationId == null) {
                continue;
            }
            if (!isRestrictableEntity(version.FirstPublishLocationId)) {
                continue;
            }

            String objectApiName = version.FirstPublishLocationId.getSObjectType().getDescribe().getName();
            String extension = resolveExtension(version.FileExtension, version.PathOnClient, version.Title);
            String errorMessage = buildRestrictionError(objectApiName, extension, rulesByObject);
            if (String.isNotBlank(errorMessage)) {
                version.addError(errorMessage);
            }
        }
    }

    @TestVisible
    static String buildRestrictionError(
        String objectApiName,
        String extension,
        Map<String, RestrictionRule> rulesByObject
    ) {
        if (String.isBlank(objectApiName) || String.isBlank(extension)) {
            return null;
        }

        RestrictionRule rule = rulesByObject.get(normalizeObjectName(objectApiName));
        if (rule == null || rule.extensions == null || rule.extensions.isEmpty()) {
            return null;
        }

        String normalizedExtension = normalizeExtension(extension);
        if (!rule.extensions.contains(normalizedExtension)) {
            return null;
        }

        String template = String.isNotBlank(rule.errorMessage) ? rule.errorMessage : DEFAULT_ERROR;
        return template
            .replace('{extension}', normalizedExtension)
            .replace('{object}', objectApiName);
    }

    @TestVisible
    static Map<String, RestrictionRule> getRulesByObject() {
        if (testRulesByObject != null) {
            return testRulesByObject;
        }

        Map<String, RestrictionRule> rulesByObject = new Map<String, RestrictionRule>();
        for (File_Extension_Restriction__mdt config : [
            SELECT Object_API_Name__c, Restricted_Extensions__c, Is_Active__c, Error_Message__c
            FROM File_Extension_Restriction__mdt
            WHERE Is_Active__c = TRUE
        ]) {
            if (String.isBlank(config.Object_API_Name__c) || String.isBlank(config.Restricted_Extensions__c)) {
                continue;
            }

            String objectKey = normalizeObjectName(config.Object_API_Name__c);
            Set<String> extensions = parseExtensions(config.Restricted_Extensions__c);

            if (rulesByObject.containsKey(objectKey)) {
                rulesByObject.get(objectKey).extensions.addAll(extensions);
                if (String.isBlank(rulesByObject.get(objectKey).errorMessage)
                    && String.isNotBlank(config.Error_Message__c)
                ) {
                    rulesByObject.get(objectKey).errorMessage = config.Error_Message__c;
                }
            } else {
                rulesByObject.put(
                    objectKey,
                    new RestrictionRule(objectKey, extensions, config.Error_Message__c)
                );
            }
        }
        return rulesByObject;
    }

    @TestVisible
    static Set<String> parseExtensions(String rawExtensions) {
        Set<String> extensions = new Set<String>();
        if (String.isBlank(rawExtensions)) {
            return extensions;
        }

        for (String token : rawExtensions.split('[,;\\s]+')) {
            String normalized = normalizeExtension(token);
            if (String.isNotBlank(normalized)) {
                extensions.add(normalized);
            }
        }
        return extensions;
    }

    @TestVisible
    static String normalizeExtension(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String normalized = value.trim().toLowerCase();
        while (normalized.startsWith('.')) {
            normalized = normalized.substring(1);
        }
        return String.isBlank(normalized) ? null : normalized;
    }

    private static String normalizeObjectName(String objectApiName) {
        return String.isBlank(objectApiName) ? null : objectApiName.trim().toLowerCase();
    }

    private static Boolean isRestrictableEntity(Id entityId) {
        if (entityId == null) {
            return false;
        }

        // Skip Users and Groups — only enforce on business records.
        Schema.SObjectType entityType = entityId.getSObjectType();
        return entityType != User.SObjectType && entityType != Group.SObjectType;
    }

    private static Map<Id, String> getLatestExtensionByDocumentId(Set<Id> documentIds) {
        Map<Id, String> extensionByDocumentId = new Map<Id, String>();
        if (documentIds == null || documentIds.isEmpty()) {
            return extensionByDocumentId;
        }

        for (ContentVersion version : [
            SELECT ContentDocumentId, FileExtension, PathOnClient, Title, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
            AND IsLatest = TRUE
        ]) {
            extensionByDocumentId.put(
                version.ContentDocumentId,
                resolveExtension(version.FileExtension, version.PathOnClient, version.Title)
            );
        }
        return extensionByDocumentId;
    }

    @TestVisible
    static String resolveExtension(String fileExtension, String pathOnClient, String title) {
        String fromField = normalizeExtension(fileExtension);
        if (String.isNotBlank(fromField)) {
            return fromField;
        }

        String fromPath = extractExtensionFromName(pathOnClient);
        if (String.isNotBlank(fromPath)) {
            return fromPath;
        }

        return extractExtensionFromName(title);
    }

    private static String extractExtensionFromName(String fileName) {
        if (String.isBlank(fileName) || !fileName.contains('.')) {
            return null;
        }
        Integer lastDot = fileName.lastIndexOf('.');
        if (lastDot < 0 || lastDot == fileName.length() - 1) {
            return null;
        }
        return normalizeExtension(fileName.substring(lastDot + 1));
    }
}
