public class MailchimpContactCreateQueueable implements Queueable, Database.AllowsCallouts {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private String operation;
    private String mailchimpSubscriberHash;

    public MailchimpContactCreateQueueable(String op, String hash) {
        this.operation = op;
        this.mailchimpSubscriberHash = hash;
    }

    public void execute(QueueableContext context) {
        if (operation == 'UPSERT') {
            try {
                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/members/' + mailchimpSubscriberHash);
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Authorization', 'apikey ' + API_KEY);
                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String contactId = (String) responseMap.get('contact_id');
                    String subscriberHash = (String) responseMap.get('id');
                    String status = (String) responseMap.get('status');
                    String email = (String) responseMap.get('email_address');
                    Map<String, Object> mergeFields = (Map<String, Object>) responseMap.get('merge_fields');
                    String firstName = (String) mergeFields.get('FNAME');
                    String lastName = (String) mergeFields.get('LNAME');
                    String phone = (String) mergeFields.get('PHONE');
                    String company = (String) mergeFields.get('COMPANY');
                    String industry = (String) mergeFields.get('INDUSTRY');
                    String accState = (String) mergeFields.get('STATE');
                    // Map<String, Object> address = String.isNotBlank(String.valueOf(mergeFields.get('ADDRESS')))
                    //     ? (Map<String, Object>) mergeFields.get('ADDRESS')
                    //     : null;
                    // String city = address != null ? (String) address.get('city') : null;
                    // String state = address != null ? (String) address.get('state') : null;
                    // String zip = address != null ? (String) address.get('zip') : null;
                    // String country = address != null ? (String) address.get('country') : null;
                    // String addr1 = address != null ? (String) address.get('addr1') : null;
                    // String addr2 = address != null ? (String) address.get('addr2') : null;

                    List<Account> accts = [SELECT Id FROM Account WHERE Name = :company];
                    Account acc = new Account();

                    if (accts.size() > 0) {
                        acc = accts[0];
                    } else {
                        acc.Name = company;
                        acc.Industry = industry;
                        // acc.BillingState = accState;
                        insert acc;
                    }

                    Contact con = new Contact(
                        Email = email,
                        FirstName = firstName,
                        LastName = lastName,
                        Mailchimp_Status__c = status,
                        Mailchimp_Contact_ID__c = contactId,
                        Mailchimp_Subscriber_Hash__c = subscriberHash,
                        AccountId = acc.Id,
                        Phone = phone
                        // MailingCity = city,
                        // MailingState = state,
                        // MailingPostalCode = zip,
                        // MailingCountryCode = country
                    );
                    System.debug('Creating Contact from Mailchimp data: ' + con);
                    upsert con Mailchimp_Subscriber_Hash__c;
                } else {
                    throw new CalloutException(
                        'Mailchimp API call failed with status ' + res.getStatusCode() + ': ' + res.getBody()
                    );
                }
            } catch (Exception e) {
                System.debug('Error during Mailchimp Contact creation: ' + e.getMessage());
                Logger__c log = new Logger__c(
                    Name = 'Mailchimp Contact Create Error',
                    Status__c = 'Failure',
                    Message__c = e.getMessage(),
                    StackTrace__c = e.getStackTraceString(),
                    Apex_Class__c = 'MailchimpContactCreateQueueable',
                    Apex_Method__c = 'execute',
                    Object_Name__c = 'Contact'
                );

                insert log;
            }
        } else if (operation == 'DELETE') {
            try {
                // Fetching contacts from Salesforce
                List<Contact> contacts = [
                    SELECT Id
                    FROM Contact
                    WHERE Mailchimp_Subscriber_Hash__c = :mailchimpSubscriberHash
                ];

                if (!contacts.isEmpty()) {
                    delete contacts;
                }
            } catch (Exception e) {
                System.debug('Error during Mailchimp Contact deletion: ' + e.getMessage());
                Logger__c log = new Logger__c(
                    Name = 'Mailchimp Contact Delete Error',
                    Status__c = 'Failure',
                    Message__c = e.getMessage(),
                    StackTrace__c = e.getStackTraceString(),
                    Apex_Class__c = 'MailchimpContactCreateQueueable',
                    Apex_Method__c = 'execute',
                    Object_Name__c = 'Contact'
                );

                insert log;
            }
        }
    }
}
