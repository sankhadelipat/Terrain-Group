public with sharing class MailchimpContactTagSyncHandler {
    public static void syncTagsToMailchimp(List<Contact> contacts, Map<Id, Contact> oldContactMap) {
        Map<Id, List<String>> contactTagsMapToAdd = new Map<Id, List<String>>();
        Map<Id, List<String>> contactTagsMapToRemove = new Map<Id, List<String>>();

        for (Contact con : contacts) {
            if (con.Email != null) {
                Contact oldCon = oldContactMap != null ? oldContactMap.get(con.Id) : null;

                // Get current and previous tags
                List<String> currentTags = con.Tags__c != null
                    ? new List<String>(con.Tags__c.split(';'))
                    : new List<String>();
                List<String> previousTags = oldCon != null &&
                    oldCon.Tags__c != null
                    ? new List<String>(oldCon.Tags__c.split(';'))
                    : new List<String>();

                // Determine tags to add and remove
                Set<String> tagsToAdd = new Set<String>(currentTags);
                tagsToAdd.removeAll(previousTags);
                System.debug('Tags to add for contact ' + con.Id + ': ' + tagsToAdd);

                Set<String> tagsToRemove = new Set<String>(previousTags);
                tagsToRemove.removeAll(currentTags);
                System.debug('Tags to remove for contact ' + con.Id + ': ' + tagsToRemove);

                // Skip if no changes
                if (tagsToAdd.isEmpty() && tagsToRemove.isEmpty()) {
                    System.debug('No tag changes for contact ' + con.Id + ', skipping.');
                    continue;
                }

                // Accumulate tags to add and remove
                if (!tagsToAdd.isEmpty()) {
                    contactTagsMapToAdd.put(con.Id, new List<String>(tagsToAdd));
                }
                if (!tagsToRemove.isEmpty()) {
                    contactTagsMapToRemove.put(con.Id, new List<String>(tagsToRemove));
                }
            }
        }

        // Enqueue jobs for adding tags
        if (!contactTagsMapToAdd.isEmpty()) {
            System.enqueueJob(new MailchimpContactTagSyncQueueable('ADD', contactTagsMapToAdd));
        }
        // Enqueue jobs for removing tags
        if (!contactTagsMapToRemove.isEmpty()) {
            System.enqueueJob(new MailchimpContactTagSyncQueueable('REMOVE', contactTagsMapToRemove));
        }
    }
}
