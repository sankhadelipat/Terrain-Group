public class MailchimpTagSyncHandler {
    // List of fields that trigger Mailchimp sync
    private static final Set<String> SYNC_FIELDS = new Set<String>{
        'Name',
        'Active__c'
        // Add other fields as necessary
    };

    public static void syncTags(List<Tag__c> newTags, Map<Id, Tag__c> oldTagMap) {
        Set<Id> tagIdsToProcess = new Set<Id>();

        for (Tag__c newTag : newTags) {
            Tag__c oldTag = oldTagMap.get(newTag.Id);

            Boolean shouldSync = false;
            // Check if any of the SYNC_FIELDS have changed
            for (String field : SYNC_FIELDS) {
                if (oldTag.get(field) != newTag.get(field)) {
                    shouldSync = true;
                    break;
                }
            }
            
            if (shouldSync) {
                tagIdsToProcess.add(newTag.Id);
            }
        }

        if (!tagIdsToProcess.isEmpty()) {
            System.enqueueJob(new MailchimpTagSyncQueueable('UPDATE', tagIdsToProcess));
        }
    }
}
