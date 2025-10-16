public class MailchimpContactTagPullBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = '23ad32226b';

    private Integer processedCount = 0;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private List<String> errorMessages = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT Id, Name, Mailchimp_Tag_ID__c
                FROM Tag__c
                WHERE Mailchimp_Tag_ID__c != NULL
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Tag__c> scope) {
        List<Tag__c> TagsToUpdate = new List<Tag__c>();
        List<Contact_Tag__c> ContactTagsToInsert = new List<Contact_Tag__c>();
        List<Contact_Tag__c> ContactTagsToDelete = new List<Contact_Tag__c>();

        for (Tag__c tag : scope) {
            try {
                // Get existing Contact emails for this tag
                Map<String, Contact_Tag__c> existingContactTags = getContactTagsMap(tag.Id);
                Set<String> existingContactEmails = existingContactTags.keySet();

                // Fetch Mailchimp contact emails for this tag
                Set<String> newContactEmails = MailchimpCampaignManager.getSegmentMembers(tag.Mailchimp_Tag_ID__c);

                // Check if sync is needed
                if (existingContactEmails.equals(newContactEmails)) {
                    tag.Sync_Status__c = 'Synced';
                    tag.Last_Sync_Date__c = System.now();
                    TagsToUpdate.add(tag);
                    successCount++;
                    continue;
                }

                // Find emails to addd
                Set<String> contactsToAdd = new Set<String>();
                for (String email : newContactEmails) {
                    if (!existingContactEmails.contains(email)) {
                        contactsToAdd.add(email);
                    }
                }

                // Find emails to remove
                Set<String> contactsToRemove = new Set<String>();
                for (String email : existingContactEmails) {
                    if (!newContactEmails.contains(email)) {
                        contactsToRemove.add(email);
                    }
                }

                // Create new Contact_Tag__c records for emails to add
                if (!contactsToAdd.isEmpty()) {
                    Map<String, Id> emailToContactId = getContactIdsByEmails(new List<String>(contactsToAdd));

                    for (String email : contactsToAdd) {
                        if (emailToContactId.get(email) == null) {
                            Contact_Tag__c contactTag = new Contact_Tag__c();
                            contactTag.Tag__c = tag.Id;
                            contactTag.Contact__c = emailToContactId.get(email);
                            ContactTagsToInsert.add(contactTag);
                        } else {
                            System.debug('No Contact found for email: ' + email);
                        }
                    }
                }

                // Remove Contact_Tag__c records for emails to remove
                if (!contactsToRemove.isEmpty()) {
                    for (String email : contactsToRemove) {
                        if (existingContactTags.get(email) != null) {
                            ContactTagsToDelete.add(existingContactTags.get(email));
                        }
                    }
                }

                // Update tag sync status
                tag.Sync_Status__c = 'Synced';
                tag.Last_Sync_Date__c = System.now();
                TagsToUpdate.add(tag);

                successCount++;

                System.debug('Synced tag: ' + tag.Id);

                // Add delay between callouts
                addCalloutDelay();
            } catch (Exception e) {
                System.debug('Error syncing tag: ' + tag.Id + ' - ' + e.getMessage());
                Tag__c failedTag = new Tag__c(
                    Id = tag.Id,
                    Sync_Status__c = 'Failed',
                    Last_Sync_Date__c = Datetime.now()
                );
                TagsToUpdate.add(failedTag);

                errorMessages.add('Error syncing tag: ' + tag.Id + ' - ' + e.getMessage());
                errorCount++;
            } finally {
                processedCount++;
            }
        }

        try {
            if (!TagsToUpdate.isEmpty()) {
                update TagsToUpdate;
            }
            if (!ContactTagsToInsert.isEmpty()) {
                insert ContactTagsToInsert;
            }
            if (!ContactTagsToDelete.isEmpty()) {
                delete ContactTagsToDelete;
            }
        } catch (DmlException dmlEx) {
            for (Tag__c tag : TagsToUpdate) {
                errorMessages.add('Error updating tag ' + tag.Name + ': ' + dmlEx.getMessage());
            }
            for (Contact_Tag__c contactTag : ContactTagsToInsert) {
                errorMessages.add('Error inserting contact tag: ' + contactTag.Id + ': ' + dmlEx.getMessage());
            }
            for (Contact_Tag__c contactTag : ContactTagsToDelete) {
                errorMessages.add('Error deleting contact tag: ' + contactTag.Id + ': ' + dmlEx.getMessage());
            }
        } finally {
            TagsToUpdate.clear();
            ContactTagsToInsert.clear();
            ContactTagsToDelete.clear();
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            'Batch Process Completed. Processed: ' +
                processedCount +
                ' Success: ' +
                successCount +
                ' Errors: ' +
                errorCount
        );

        if (!errorMessages.isEmpty()) {
            for (String errMsg : errorMessages) {
                System.debug('Error: ' + errMsg);
            }

            Logger__c log = new Logger__c(
                Name = 'Mailchimp Contact Tag Pull Batch',
                Status__c = errorCount > 0 ? 'Completed with Errors' : 'Success',
                Message__c = 'Processed: ' +
                    processedCount +
                    ', Success: ' +
                    successCount +
                    ', Errors: ' +
                    errorCount +
                    (errorCount > 0 ? '. Check debug logs for details.' : ''),
                StackTrace__c = errorCount > 0 ? String.join(errorMessages, '\n') : null,
                Apex_Class__c = 'MailchimpContactTagPullBatch',
                Apex_Method__c = 'finish',
                Object_Name__c = 'Contact'
            );
            insert log;
        }
    }

    private Map<String, Contact_Tag__c> getContactTagsMap(Id tagId) {
        Map<String, Contact_Tag__c> contactTagsMap = new Map<String, Contact_Tag__c>();

        List<Contact_Tag__c> contacts = [
            SELECT Id, Contact__r.Email, Contact__c
            FROM Contact_Tag__c
            WHERE Tag__c = :tagId
        ];

        for (Contact_Tag__c contactTag : contacts) {
            if (contactTag.Contact__r.Email != null && contactTag.Contact__c != null) {
                String normalizedEmail = contactTag.Contact__r.Email.toLowerCase();
                contactTagsMap.put(contactTag.Contact__r.Email, contactTag);
            }
        }

        return contactTagsMap;
    }

    private Map<String, Id> getContactIdsByEmails(List<String> emails) {
        Map<String, Id> emailToContactId = new Map<String, Id>();

        if (emails.isEmpty()) {
            return emailToContactId;
        }

        // Normalize emails for case-insensitive comparison
        Set<String> normalizedEmails = new Set<String>();
        for (String email : emails) {
            normalizedEmails.add(email.toLowerCase());
        }

        List<Contact> contacts = [
            SELECT Id, Email
            FROM Contact
            WHERE Email IN :normalizedEmails
        ];

        for (Contact con : contacts) {
            emailToContactId.put(con.Email.toLowerCase(), con.Id);
        }

        return emailToContactId;
    }

    private void addCalloutDelay() {
        if (Limits.getCallouts() < Limits.getLimitCallouts()) {
            Integer delay = 100; // 100ms delay
            Long startingTime = System.currentTimeMillis();
            while (System.currentTimeMillis() - startingTime < delay) {
                // Busy wait for the specified delay
            }
        }
    }
}
