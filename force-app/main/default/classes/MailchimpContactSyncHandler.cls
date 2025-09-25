public class MailchimpContactSyncHandler {
    // List of fields that trigger Mailchimp sync
    private static final Set<String> SYNC_FIELDS = new Set<String>{
        'Email',
        'Phone',
        'MobilePhone',
        'Fax',
        'Birthdate',
        'Description',
        'FirstName',
        'LastName',
        'Phone',
        'Mailchimp_Subscriber_Hash__c',
        'Mailchimp_Contact_ID__c',
        // 'Mailchimp_Status__c',
        'OwnerId',
        'MailingStreet',
        'MailingCity',
        'MailingState',
        'MailingPostalCode',
        'MailingCountry'
    };

    public static void syncContacts(Map<Id, Contact> oldMap, Map<Id, Contact> newMap) {
        Set<Id> contactIds = new Set<Id>();

        for (Id conId : newMap.keySet()) {
            Contact oldCon = oldMap.get(conId);
            Contact newCon = newMap.get(conId);

            Boolean shouldSync = false;

            // Check if any of the SYNC_FIELDS have changed
            for (String field : SYNC_FIELDS) {
                if (oldCon.get(field) != newCon.get(field)) {
                    shouldSync = true;
                    break;
                }
            }

            if (shouldSync) {
                contactIds.add(conId);
            }
        }
        
        if (!contactIds.isEmpty()) {
            // Enqueue the Queueable job to sync contacts
            System.enqueueJob(new MailchimpContactSyncQueueable('UPSERT', contactIds));
        }
    }
}
