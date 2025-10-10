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
                SELECT Id, Email, Tags__c, Mailchimp_Subscriber_Hash__c
                FROM Contact
                WHERE Email != NULL
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        List<Contact> contactsToUpdate = new List<Contact>();

        for (Contact con : scope) {
            try {
                // Derive subscriber hash
                String subscriberHash = !String.isBlank(con.Mailchimp_Subscriber_Hash__c)
                    ? con.Mailchimp_Subscriber_Hash__c
                    : generateMD5Hash(con.Email.toLowerCase());

                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/members/' + subscriberHash);
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Authorization', 'apikey ' + API_KEY);
                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    List<Object> tags = (List<Object>) responseMap.get('tags');

                    Set<String> tagNames = new Set<String>();
                    for (Object tagObj : tags) {
                        Map<String, Object> tagMap = (Map<String, Object>) tagObj;
                        String tagName = (String) tagMap.get('name');
                        tagNames.add(tagName);
                    }

                    Set<String> existingTagNames = new Set<String>();
                    if (!String.isBlank(con.Tags__c)) {
                        existingTagNames = new Set<String>(con.Tags__c.split(';'));
                    }

                    if (!tagNames.equals(existingTagNames)) {
                        String tagsString = String.join(tagNames, ';');
                        Contact updatedCon = new Contact(Id = con.Id, Tags__c = tagsString);
                        contactsToUpdate.add(updatedCon);
                    }

                    successCount++;
                } else {
                    errorCount++;
                    errorMessages.add(
                        'Failed to fetch member for Contact ID ' +
                            con.Id +
                            ': ' +
                            res.getStatusCode() +
                            ' - ' +
                            res.getBody()
                    );
                }
            } catch (Exception e) {
                errorCount++;
                errorMessages.add('Error processing Contact ID ' + con.Id + ': ' + e.getMessage());
            } finally {
                processedCount++;
            }
        }

        if (!contactsToUpdate.isEmpty()) {
            try {
                update contactsToUpdate;
            } catch (DmlException dmlEx) {
                for (Contact c : contactsToUpdate) {
                    errorMessages.add('DML Error updating Contact ID ' + c.Id + ': ' + dmlEx.getMessage());
                }
            } finally {
                contactsToUpdate.clear();
            }
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

    // Helper method to generate MD5 hash for Mailchimp member ID
    private String generateMD5Hash(String input) {
        Blob targetBlob = Blob.valueOf(input);
        Blob md5hash = Crypto.generateDigest('MD5', targetBlob);
        return EncodingUtil.convertToHex(md5hash);
    }
}
