public class MailchimpTagSyncQueueable implements Queueable, Database.AllowsCallouts {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private String operation; // 'INSERT', 'UPDATE', 'DELETE' OR 'TAG_CONTACTS'
    private Set<Id> recordIds;

    public MailchimpTagSyncQueueable(String op, Set<Id> ids) {
        this.operation = op;
        this.recordIds = ids;
    }

    public void execute(QueueableContext context) {
        List<Tag__c> tagsToSync = new List<Tag__c>();
        // Query Tags with neessary fields
        List<Tag__c> tags = [
            SELECT Id, Name, Mailchimp_Tag_ID__c
            FROM Tag__c
            WHERE Id IN :recordIds
        ];

        try {
            // Prepare HTTP request
            Http http = new Http();

            for (Tag__c tag : tags) {
                HttpRequest req = new HttpRequest();

                if (operation == 'INSERT') {
                    // Get all tag member emails
                    List<String> memberEmails = MailchimpTagManager.getTagMemberEmails(tag.Id);

                    String requestBody = JSON.serialize(
                        new Map<String, Object>{ 'name' => tag.Name, 'satic_segment' => memberEmails }
                    );

                    // Create tag in Mailchimp
                    req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments');
                    req.setHeader('Content-Type', 'application/json');
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('POST');
                    req.setBody(requestBody);
                } else if (operation == 'TAG_CONTACTS') {
                    // Get all tag member emails
                    List<String> memberEmails = MailchimpTagManager.getTagMemberEmails(tag.Id);

                    // Update tag members in Mailchimp
                    MailchimpCampaignManager.updateSegmentMembers(tag.Mailchimp_Tag_ID__c, memberEmails);
                } else if (operation == 'UPDATE') {
                    if (String.isBlank(tag.Mailchimp_Tag_ID__c)) {
                        System.debug('Skipping delete for tag with no Mailchimp ID: ' + tag.Id);
                        continue;
                    }
                    // Update tag in Mailchimp
                    String requestBody = JSON.serialize(new Map<String, Object>{ 'name' => tag.Name });

                    req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments/' + tag.Mailchimp_Tag_ID__c);
                    req.setHeader('Content-Type', 'application/json');
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('PATCH');
                    req.setBody(requestBody);
                } else if (operation == 'DELETE') {
                    if (String.isBlank(tag.Mailchimp_Tag_ID__c)) {
                        System.debug('Skipping delete for tag with no Mailchimp ID: ' + tag.Id);
                        continue;
                    }
                    // Delete tag in Mailchimp
                    req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments/' + tag.Mailchimp_Tag_ID__c);
                    req.setHeader('Content-Type', 'application/json');
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('DELETE');
                }

                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200 || res.getStatusCode() == 204) {
                    System.debug('Mailchimp Tag Sync Response: ' + res.getBody());
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String mailchimpTagId = String.valueOf(responseMap.get('id'));

                    if (operation == 'INSERT') {
                        Tag__c newTag = new Tag__c(
                            Id = tag.Id,
                            Mailchimp_Tag_ID__c = mailchimpTagId,
                            Sync_Status__c = 'Synced',
                            Last_Sync_Date__c = Datetime.now()
                        );
                        tagsToSync.add(newTag);
                    }
                    //   else if (operation == 'DELETE') {
                    //   }
                } else {
                    Tag__c failedTag = new Tag__c(
                        Name = tag.Name,
                        Sync_Status__c = 'Failed',
                        Last_Sync_Date__c = Datetime.now()
                    );
                    tagsToSync.add(failedTag);

                    System.debug('Error syncing tag: ' + res.getBody());
                    throw new CalloutException('Error syncing tag');
                }
            }

            if (!tagsToSync.isEmpty()) {
                update tagsToSync;
            }
        } catch (Exception e) {
            System.debug('Error syncing tags: ' + e.getMessage());

            Logger__c log = new Logger__c(
                Name = 'Mailchimp Tag Sync Error',
                Status__c = 'Failure',
                Message__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(),
                Apex_Class__c = 'MailchimpTagSyncQueueable',
                Apex_Method__c = 'execute',
                Object_Name__c = 'Tag__c'
            );
            insert log;
        }
    }
}
