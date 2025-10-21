public class MailchimpContactSyncQueueable implements Queueable, Database.AllowsCallouts {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private String operation; // 'UPSERT' or 'DELETE'
    private Set<Id> recordIds;

    public MailchimpContactSyncQueueable(String op, Set<Id> ids) {
        this.operation = op;
        this.recordIds = ids;
    }

    public void execute(QueueableContext context) {
        List<Contact> contactsToSync = new List<Contact>();
        // List<Contact> contactsToDelete = new List<Contact>();

        // Query Contacts with neessary fields
        List<Contact> contacts = [
            SELECT
                Id,
                Email,
                FirstName,
                LastName,
                AccountId,
                Account.Name,
                Account.Industry,
                AccountStateMC__c,
                Phone,
                Mailchimp_Status__c,
                Mailchimp_Contact_ID__c,
                Mailchimp_Subscriber_Hash__c
            FROM Contact
            WHERE Id IN :recordIds
            ALL ROWS
        ];

        try {
            // Prepare HTTP request
            Http http = new Http();

            for (Contact con : contacts) {
                HttpRequest req = new HttpRequest();

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

                if (operation == 'UPSERT') {
                    // Build the JSON Body for Mailchimp
                    Map<String, Object> body = new Map<String, Object>{
                        'email_address' => con.Email,
                        'status_if_new' => 'subscribed',
                        'merge_fields' => new Map<String, String>{ 'FNAME' => con.FirstName, 'LNAME' => con.LastName }
                    };

                    // Optionally add phone and company if available
                    if (String.isNotBlank(con.Phone)) {
                        ((Map<String, String>) body.get('merge_fields')).put('PHONE', con.Phone);
                    }
                    if (con.AccountId != null && String.isNotBlank(con.Account.Name)) {
                        ((Map<String, String>) body.get('merge_fields')).put('COMPANY', con.Account.Name);
                    }
                    if (String.isNotBlank(con.Account.Industry)) {
                        ((Map<String, String>) body.get('merge_fields')).put('INDUSTRY', con.Account.Industry);
                    }
                    if (String.isNotBlank(con.AccountStateMC__c)) {
                        ((Map<String, String>) body.get('merge_fields')).put('STATE', con.AccountStateMC__c);
                    }

                    String jsonBody = JSON.serialize(body);

                    req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/members/' + subscriberHash);
                    req.setHeader('Content-Type', 'application/json');
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('PUT');
                    req.setBody(jsonBody);
                } else if (operation == 'DELETE') {
                    req.setEndpoint(
                        BASE_URL + '/lists/' + LIST_ID + '/members/' + subscriberHash + '/actions/delete-permanent'
                    );
                    req.setHeader('Content-Type', 'application/json');
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('POST');
                }

                HttpResponse res = http.send(req);
                System.debug('Mailchimp Response: ' + res.getBody());

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                    if (operation == 'UPSERT') {
                        Contact updatedCon = new Contact(
                            Id = con.Id,
                            // Mailchimp_Status__c = (String) responseMap.get('status'),
                            Mailchimp_Contact_ID__c = (String) responseMap.get('contact_id'),
                            Mailchimp_Subscriber_Hash__c = (String) responseMap.get('id')
                        );

                        contactsToSync.add(updatedCon);
                    }
                } else if (res.getStatusCode() == 204) {
                    // if (operation == 'DELETE') {
                    //     contactsToDelete.add(con);
                    // }
                } else {
                    throw new CalloutException(
                        'Mailchimp API call failed with status ' + res.getStatusCode() + ': ' + res.getBody()
                    );
                }
            }

            // Update Contacts with new Mailchimp IDs
            if (!contactsToSync.isEmpty()) {
                update contactsToSync;
            }

            // Delete Contacts from Mailchimp
            // if (!contactsToDelete.isEmpty()) {
            //     Database.emptyRecycleBin(contactsToDelete);
            // }
        } catch (Exception e) {
            System.debug('Error during Mailchimp sync: ' + e.getMessage());
            Logger__c log = new Logger__c(
                Name = 'Mailchimp Contact Sync Error',
                Status__c = 'Failure',
                Message__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(),
                Apex_Class__c = 'MailchimpContactSyncQueueable',
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
