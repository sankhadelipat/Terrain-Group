public class MailchimpContactTagSyncQueueable implements Queueable, Database.AllowsCallouts {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private String action; // 'ADD' or 'REMOVE'
    private Map<Id, List<String>> contactTagsMap;

    public MailchimpContactTagSyncQueueable(String action, Map<Id, List<String>> contactTagsMap) {
        this.action = action;
        this.contactTagsMap = contactTagsMap;
    }

    public void execute(QueueableContext context) {
        List<Contact> contacts = [
            SELECT Id, Email, Mailchimp_Subscriber_Hash__c
            FROM Contact
            WHERE Id IN :contactTagsMap.keySet()
        ];

        try {
            // Prepare HTTP request
            Http http = new Http();

            for (Contact con : contacts) {
                // Determine subscriber hash
                String subscriberHash;
                if (String.isNotBlank(con.Mailchimp_Subscriber_Hash__c)) {
                    subscriberHash = con.Mailchimp_Subscriber_Hash__c;
                } else if (String.isNotBlank(con.Email)) {
                    subscriberHash = generateMD5Hash(con.Email.toLowerCase());
                } else {
                    System.debug('Skipping contact with no email and no subscriber hash: ' + con.Id);
                    continue;
                }

                List<String> tags = contactTagsMap.get(con.Id);
                List<Map<String, Object>> tagsPayload = new List<Map<String, Object>>();

                if (action == 'ADD') {
                    // Build the JSON Body for adding tags
                    for (String tag : tags) {
                        tagsPayload.add(new Map<String, Object>{ 'name' => tag, 'status' => 'active' });
                    }
                } else if (action == 'REMOVE') {
                    // Build the JSON Body for removing tags
                    for (String tag : tags) {
                        tagsPayload.add(new Map<String, Object>{ 'name' => tag, 'status' => 'inactive' });
                    }
                }

                HttpRequest req = new HttpRequest();
                req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/members/' + subscriberHash + '/tags');
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Authorization', 'apikey ' + API_KEY);
                req.setMethod('POST');
                req.setBody(JSON.serialize(new Map<String, Object>{ 'tags' => tagsPayload }));

                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 204) {
                    System.debug('Tags synced successfully for contact: ' + con.Id);
                } else {
                    System.debug(
                        'Failed to sync tags for contact: ' +
                            con.Id +
                            ', Status: ' +
                            res.getStatusCode() +
                            ', Body: ' +
                            res.getBody()
                    );
                    throw new CalloutException('Failed to sync tags for contact: ' + con.Id);
                }
            }
        } catch (Exception e) {
            System.debug('Error syncing tags: ' + e.getMessage());
            Logger__c log = new Logger__c(
                Name = 'Mailchimp Tag Sync Error',
                Status__c = 'Failure',
                Message__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(),
                Apex_Class__c = 'MailchimpContactTagSyncQueueable',
                Apex_Method__c = 'execute',
                Object_Name__c = 'Contact'
            );

            insert log;
        }
    }

    // Helper method to generate MD5 hash for Mailchimp member ID
    private String generateMD5Hash(String input) {
        Blob targetBlob = Blob.valueOf(input);
        Blob md5hash = Crypto.generateDigest('MD5', targetBlob);
        return EncodingUtil.convertToHex(md5hash);
    }
}
