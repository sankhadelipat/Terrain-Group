public class MailchimpCampaignMemberPullBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private Integer processedCount = 0;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private List<String> errorMessages = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT Id, Name, Mailchimp_Campaign_ID__c, Mailchimp_Segment_ID__c, Mailchimp_Web_ID__c, Sync_Status__c
                FROM Campaign
                WHERE Mailchimp_Campaign_ID__c != NULL AND Mailchimp_Segment_ID__c != NULL AND IsActive = TRUE
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Campaign> scope) {
        List<Campaign> campaignsToUpdate = new List<Campaign>();
        List<CampaignMember> membersToInsert = new List<CampaignMember>();
        List<CampaignMember> membersToDelete = new List<CampaignMember>();

        for (Campaign camp : scope) {
            try {
                // Get existing campaign member emails in Salesforce
                Map<String, CampaignMember> existingMembersMap = getCampaignMemberMap(camp.Id);
                Set<String> existingMemberEmails = existingMembersMap.keySet();

                // Fetch campaign members from Mailchimp
                Set<String> newMemberEmails = MailchimpCampaignManager.getSegmentMembers(camp.Mailchimp_Segment_ID__c);

                // Check if sync is needed
                if (existingMemberEmails.equals(newMemberEmails)) {
                    camp.Sync_Status__c = 'Synced';
                    camp.Last_Sync_Date__c = System.now();
                    campaignsToUpdate.add(camp);
                    successCount++;
                    continue; // No changes needed
                }

                // Find emails to add
                Set<String> membersToAdd = new Set<String>();
                for (String email : newMemberEmails) {
                    if (!existingMemberEmails.contains(email)) {
                        membersToAdd.add(email);
                    }
                }

                // Find emails to remove
                Set<String> membersToRemove = new Set<String>();
                for (String email : existingMemberEmails) {
                    if (!newMemberEmails.contains(email)) {
                        membersToRemove.add(email);
                    }
                }

                // Create new campaign members for added emails
                if (!membersToAdd.isEmpty()) {
                    Map<String, Id> emailToContactId = getContactIdsByEmails(new List<String>(membersToAdd));

                    for (String email : membersToAdd) {
                        if (emailToContactId.containsKey(email.toLowerCase())) {
                            CampaignMember newMember = new CampaignMember(
                                CampaignId = camp.Id,
                                ContactId = emailToContactId.get(email.toLowerCase()),
                                Status = 'Sent'
                            );
                            membersToInsert.add(newMember);
                        } else {
                            System.debug('No Contact found for email: ' + email);
                        }
                    }
                }

                // Remove campaign members for deleted emails
                if (!membersToRemove.isEmpty()) {
                    for (String email : membersToRemove) {
                        if (existingMembersMap.containsKey(email)) {
                            membersToDelete.add(existingMembersMap.get(email));
                        }
                    }
                }

                // Update campaign sync status
                camp.Sync_Status__c = 'Synced';
                camp.Last_Sync_Date__c = System.now();
                campaignsToUpdate.add(camp);
                successCount++;

                System.debug(
                    'Campaign ' +
                        camp.Name +
                        ': Added ' +
                        membersToAdd.size() +
                        ' members, Removed ' +
                        membersToRemove.size() +
                        ' members.'
                );

                // Add delay between callouts
                addCalloutDelay();
            } catch (Exception e) {
                camp.Sync_Status__c = 'Error';
                campaignsToUpdate.add(camp);

                errorMessages.add('Error processing campaign ' + camp.Name + ': ' + e.getMessage());
                errorCount++;
            } finally {
                processedCount++;
            }
        }

        try {
            if (!campaignsToUpdate.isEmpty()) {
                update campaignsToUpdate;
            }
            if (!membersToInsert.isEmpty()) {
                insert membersToInsert;
            }
            if (!membersToDelete.isEmpty()) {
                delete membersToDelete;
            }
        } catch (DmlException dmlEx) {
            for (Campaign c : campaignsToUpdate) {
                errorMessages.add('DML Error updating Campaign ID ' + c.Id + ': ' + dmlEx.getMessage());
            }
            for (CampaignMember cm : membersToInsert) {
                errorMessages.add(
                    'DML Error inserting CampaignMember for Campaign ID ' + cm.CampaignId + ': ' + dmlEx.getMessage()
                );
            }
            for (CampaignMember cm : membersToDelete) {
                errorMessages.add('DML Error deleting CampaignMember ID ' + cm.Id + ': ' + dmlEx.getMessage());
            }
            errorCount += campaignsToUpdate.size() + membersToInsert.size() + membersToDelete.size();
        } finally {
            campaignsToUpdate.clear();
            membersToInsert.clear();
            membersToDelete.clear();
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            'Batch Process Completed. Processed: ' +
                processedCount +
                ', Success: ' +
                successCount +
                ', Errors: ' +
                errorCount
        );

        if (!errorMessages.isEmpty()) {
            for (String errMsg : errorMessages) {
                System.debug('Error: ' + errMsg);
            }

            Logger__c log = new Logger__c(
                Name = 'Mailchimp Campaign Member Pull Batch',
                Status__c = errorCount > 0 ? 'Completed with Errors' : 'Success',
                Message__c = 'Processed: ' +
                    processedCount +
                    ', Success: ' +
                    successCount +
                    ', Errors: ' +
                    errorCount +
                    (errorCount > 0 ? ', See debug logs for details.' : ''),
                StackTrace__c = String.join(errorMessages, '\n'),
                Apex_Class__c = 'MailchimpCampaignMemberPullBatch',
                Apex_Method__c = 'finish',
                Object_Name__c = 'CampaignMember'
            );
            insert log;
        }
    }

    private Map<String, CampaignMember> getCampaignMemberMap(Id campaignId) {
        Map<String, CampaignMember> emailToMemberMap = new Map<String, CampaignMember>();

        List<CampaignMember> members = [
            SELECT Id, Contact.Email, ContactId
            FROM CampaignMember
            WHERE CampaignId = :campaignId AND Contact.Email != NULL
        ];

        for (CampaignMember cm : members) {
            if (cm.Contact != null && cm.Contact.Email != null) {
                String normalizedEmail = cm.Contact.Email.toLowerCase();
                emailToMemberMap.put(normalizedEmail, cm);
            }
        }

        return emailToMemberMap;
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
